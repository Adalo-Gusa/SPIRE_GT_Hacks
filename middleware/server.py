"""HeirLoom middleware. Owns every provider credential; the iOS app only holds HEIRLOOM_API_TOKEN.

  uvicorn server:app --host 0.0.0.0 --port 8000

Routes match heirloom_GT/HeirLoom/Data/Services/VultrMiddlewareClient.swift.
"""

from __future__ import annotations

import hmac
import logging
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from uuid import UUID

from backboard import BackboardClient
from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pymongo.errors import PyMongoError

from env import load_env, require
from family_memory import FamilyMemory
from grok import GrokClient, ProviderError
from loom_session import LOOM_SYSTEM_PROMPT, LoomSession
from models import (
    ChatRequest,
    FamilyGraph,
    FollowUpRequest,
    FollowUpResponse,
    IllustrationRequest,
    IllustrationResponse,
    IngestRequest,
    LoomSpark,
    MemoryIngestionResult,
    MemoryNode,
    StorybookRequest,
    StoryChapter,
)
from pipeline import LoomPipeline, UnknownMemberError
from store import MongoFamilyStore

logger = logging.getLogger("heirloom.server")
SERVER_STATE_PATH = Path(__file__).with_name(".server_session_state.json")


@dataclass
class Services:
    pipeline: LoomPipeline
    chat: ChatBackend
    api_token: str


class ChatBackend:
    """Loom conversation on the family's Backboard assistant, one thread per app session id."""

    def __init__(self, session: LoomSession, memory: FamilyMemory, family_id: str) -> None:
        self._session = session
        self._memory = memory
        self._family_id = family_id

    async def reply(self, message: str, session_id: str) -> str:
        assistant_id = await self._memory.assistant_for(self._family_id)
        reply = await self._session.send(
            message,
            session=session_id,
            system_prompt=LOOM_SYSTEM_PROMPT,
            assistant_id=assistant_id,
        )
        return reply.content


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    if getattr(app.state, "services", None) is not None:
        yield
        return
    load_env()
    logging.basicConfig(level=logging.INFO)
    family_id = os.environ.get("HEIRLOOM_FAMILY_ID", "fam_clarke_001")
    store = MongoFamilyStore.from_env()
    grok = GrokClient.from_env()
    backboard = BackboardClient(api_key=require("BACKBOARD_API_KEY"))
    memory = FamilyMemory(backboard, store)
    try:
        await store.ensure_indexes()
    except PyMongoError:
        logger.exception("Could not reach Atlas at startup; requests will retry")
    app.state.services = Services(
        pipeline=LoomPipeline(store, grok, memory, family_id),
        chat=ChatBackend(LoomSession(backboard, SERVER_STATE_PATH), memory, family_id),
        api_token=require("HEIRLOOM_API_TOKEN"),
    )
    try:
        yield
    finally:
        await grok.close()
        await store.close()


app = FastAPI(title="HeirLoom middleware", lifespan=lifespan)
bearer = HTTPBearer(auto_error=False)


def services(request: Request) -> Services:
    return request.app.state.services


def authorized(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    svc: Services = Depends(services),
) -> Services:
    token = credentials.credentials if credentials else ""
    if not hmac.compare_digest(token.encode(), svc.api_token.encode()):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or missing token", {"WWW-Authenticate": "Bearer"})
    return svc


@app.exception_handler(ProviderError)
async def provider_error(_: Request, error: ProviderError) -> JSONResponse:
    return JSONResponse({"detail": str(error)}, status_code=status.HTTP_502_BAD_GATEWAY)


@app.exception_handler(PyMongoError)
async def database_error(_: Request, error: PyMongoError) -> JSONResponse:
    logger.error("Atlas error: %s", error)
    return JSONResponse({"detail": "The family database is unavailable."}, status_code=status.HTTP_503_SERVICE_UNAVAILABLE)


@app.exception_handler(UnknownMemberError)
async def unknown_member(_: Request, error: UnknownMemberError) -> JSONResponse:
    return JSONResponse({"detail": str(error)}, status_code=status.HTTP_404_NOT_FOUND)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/graph", response_model=FamilyGraph)
async def graph(svc: Services = Depends(authorized)) -> FamilyGraph:
    return await svc.pipeline.store.graph(svc.pipeline.family_id)


@app.post("/memories", status_code=status.HTTP_204_NO_CONTENT)
async def add_memory(memory: MemoryNode, svc: Services = Depends(authorized)) -> Response:
    await svc.pipeline.store.insert_memory(svc.pipeline.family_id, memory)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post("/memories/ingest", response_model=MemoryIngestionResult)
async def ingest(body: IngestRequest, background: BackgroundTasks, svc: Services = Depends(authorized)) -> MemoryIngestionResult:
    transcript = body.transcript.strip()
    if not transcript:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Transcript is empty")
    result, author = await svc.pipeline.ingest(transcript, body.author_id)
    background.add_task(svc.pipeline.finish_in_background, result.memory, author.name)
    return result


@app.get("/sparks/{member_id}", response_model=list[LoomSpark])
async def pending_sparks(member_id: UUID, svc: Services = Depends(authorized)) -> list[LoomSpark]:
    return await svc.pipeline.store.pending_sparks(svc.pipeline.family_id, member_id)


@app.post("/sparks/{spark_id}/resolve", status_code=status.HTTP_204_NO_CONTENT)
async def resolve_spark(spark_id: UUID, svc: Services = Depends(authorized)) -> Response:
    if not await svc.pipeline.store.resolve_spark(svc.pipeline.family_id, spark_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No such spark")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post("/agent/followups", response_model=FollowUpResponse)
async def follow_ups(body: FollowUpRequest, svc: Services = Depends(authorized)) -> FollowUpResponse:
    return FollowUpResponse(questions=await svc.pipeline.follow_ups(body.memory))


@app.post("/agent/chat")
async def chat(body: ChatRequest, svc: Services = Depends(authorized)) -> StreamingResponse:
    try:
        reply = await svc.chat.reply(body.message, body.session_id)
    except Exception as error:
        logger.exception("Backboard chat failed")
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Loom could not reply right now.") from error

    async def lines() -> AsyncIterator[str]:
        # The client reads one line per chunk and drops the newline, so keep the reply on one line.
        yield " ".join(reply.split()) + "\n"

    return StreamingResponse(lines(), media_type="text/plain; charset=utf-8")


@app.post("/storybook", response_model=list[StoryChapter])
async def storybook(body: StorybookRequest, svc: Services = Depends(authorized)) -> list[StoryChapter]:
    return await svc.pipeline.storybook(body.memory_ids)


@app.post("/storybook/illustration", response_model=IllustrationResponse)
async def illustration(body: IllustrationRequest, svc: Services = Depends(authorized)) -> IllustrationResponse:
    return IllustrationResponse(url=await svc.pipeline.grok.generate_image(body.prompt))
