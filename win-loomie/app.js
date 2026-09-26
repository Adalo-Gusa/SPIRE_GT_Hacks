const VOICE_INSTRUCTIONS = `You are Loomie, a warm family oral historian speaking out loud in a live conversation.

If they say hi, hello, or how are you, greet them back warmly and wait. Do not launch into interview questions until they share a story.

Remember everything they say in this session. When they later ask what they told you, who was with them, or where they worked, answer from this conversation and the known family memories. Never say you forgot or that you have no memory.

When they share a story, acknowledge a concrete detail and you may ask one gentle follow-up. Keep spoken replies to 1–3 sentences.`;

const SAMPLE_RATE = 24000;
const transcriptEl = document.querySelector("#transcript");
const draftEl = document.querySelector("#draft");
const actionEl = document.querySelector("#action");
const statusEl = document.querySelector("#status");
const memoryTestEl = document.querySelector("#memory-test");
const storyTestEl = document.querySelector("#story-test");
const mongoTestEl = document.querySelector("#mongo-test");
const searchConnectionsEl = document.querySelector("#search-connections");
const viewCorkboardEl = document.querySelector("#view-corkboard");
const corkboardOverlayEl = document.querySelector("#corkboard-overlay");
const corkboardCloseEl = document.querySelector("#corkboard-close");
const corkboardRefreshEl = document.querySelector("#corkboard-refresh");
const corkboardSvgEl = document.querySelector("#corkboard-svg");
const corkboardCardsEl = document.querySelector("#corkboard-cards");
const wrapUpStoryEl = document.querySelector("#wrap-up-story");
const newThreadEl = document.querySelector("#new-thread");
const artifactCardEl = document.querySelector("#artifact-card");
const barsEl = actionEl.querySelector(".bars");
const sendEl = actionEl.querySelector(".send");

let threadId = crypto.randomUUID();
let busy = false;
const messages = [];
let savedArtifact = null;
let voice;

function addLine(sender, text, streaming = false) {
  const line = { id: crypto.randomUUID(), sender, text, streaming };
  messages.push(line);
  render();
  return line;
}

function finishStreaming() {
  for (const line of messages) line.streaming = false;
}

function updateStreaming(sender, text) {
  const existing = [...messages].reverse().find((line) => line.sender === sender && line.streaming);
  if (existing) existing.text = text;
  else addLine(sender, text, true);
  render();
}

function hasStoryTurns() {
  return messages.some((line) => {
    const text = (line.text || "").trim();
    return (line.sender === "You" || line.sender === "Loomie") && text && text !== "…";
  });
}

function renderArtifact() {
  if (!savedArtifact) {
    artifactCardEl.hidden = true;
    artifactCardEl.replaceChildren();
    return;
  }
  artifactCardEl.hidden = false;
  const mongoHtml = savedArtifact.mongo_saved
    ? `<div class="mongo-badge">🍃 MongoDB Atlas: ${escapeHtml(savedArtifact.story_id || "Saved")}${savedArtifact.spark_id ? ` · Spark: ${escapeHtml(savedArtifact.spark_id)}` : ""}</div>`
    : "";
  artifactCardEl.innerHTML = `
    <h3>${escapeHtml(savedArtifact.title)}</h3>
    <p>${escapeHtml(savedArtifact.narrativeSummary)}</p>
    <div class="meta">
      <div><strong>Author:</strong> ${escapeHtml(savedArtifact.authorName || "Joseph Clarke")}</div>
      <div><strong>Era:</strong> ${escapeHtml(savedArtifact.extractedEra || "—")}</div>
      <div><strong>Location:</strong> ${escapeHtml(savedArtifact.location || "—")}</div>
      <div><strong>People:</strong> ${escapeHtml((savedArtifact.peopleMentioned || []).join(", ") || "—")}</div>
      <div><strong>Passions:</strong> ${escapeHtml((savedArtifact.passionsOrHobbies || []).join(", ") || "—")}</div>
      <div><strong>Imagine Prompt:</strong> <em>${escapeHtml(savedArtifact.grokImaginePrompt || "—")}</em></div>
      ${mongoHtml}
    </div>
  `;
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text ?? "";
  return div.innerHTML;
}

function render() {
  transcriptEl.replaceChildren();
  for (const line of messages) {
    const article = document.createElement("article");
    article.className = `line ${line.sender.toLowerCase()}`;
    const who = document.createElement("span");
    who.className = "who";
    who.textContent = line.sender;
    const body = document.createElement("div");
    body.textContent = line.text;
    article.append(who, body);
    transcriptEl.append(article);
  }
  transcriptEl.scrollTop = transcriptEl.scrollHeight;
  const live = voice.phase !== "idle";
  const trimmed = draftEl.value.trim();
  const showSend = trimmed.length > 0;
  barsEl.hidden = showSend;
  sendEl.hidden = !showSend;
  actionEl.className = live && !showSend ? `primary live ${voice.phase}` : showSend ? "primary" : "ghost";
  actionEl.disabled = busy;
  actionEl.setAttribute("aria-label", showSend ? "Send" : live ? "Stop voice" : "Start voice");
  if (live && !showSend) {
    actionEl.title = "Hangs up. Loomie answers on her own when you pause.";
    actionEl.setAttribute("aria-valuetext", voice.sessionId);
  } else {
    actionEl.removeAttribute("aria-valuetext");
    actionEl.title = "";
  }
  const placeholder = {
    idle: "Say hi, or tell Loomie a story…",
    connecting: "Connecting…",
    listening: "Listening…",
    thinking: "Thinking…",
    speaking: "Speaking…",
  }[voice.phase];
  draftEl.placeholder = placeholder;
  statusEl.textContent = live ? `${placeholder} session ${voice.sessionId}` : placeholder;
  memoryTestEl.disabled = busy || live;
  storyTestEl.disabled = busy || live;
  if (mongoTestEl) mongoTestEl.disabled = busy || live;
  if (searchConnectionsEl) searchConnectionsEl.disabled = busy || live;
  if (viewCorkboardEl) viewCorkboardEl.disabled = busy;
  if (wrapUpStoryEl) wrapUpStoryEl.disabled = busy || live || !hasStoryTurns();
  if (newThreadEl) newThreadEl.disabled = busy;
  draftEl.disabled = busy;
  renderArtifact();
}

class VoiceLogger {
  constructor(sessionId) {
    this.sessionId = sessionId;
    this.started = performance.now();
    this.buffer = [];
    this.timer = setInterval(() => this.flush(false), 1000);
  }

  log(kind, data = {}) {
    const entry = {
      ...redact(data),
      kind,
      t: Math.round(performance.now() - this.started),
      ts: Date.now(),
    };
    this.buffer.push(entry);
    if (this.buffer.length >= 200) this.flush(false);
  }

  server(event) {
    this.log("server", redactEvent(event));
  }

  client(event) {
    this.log("client", redactEvent(event));
  }

  error(where, message) {
    this.log("error", { where, message: clip(message) });
  }

  close() {
    clearInterval(this.timer);
    this.flush(true);
  }

  flush(final) {
    if (!this.buffer.length) return;
    const entries = this.buffer.splice(0, 500);
    fetch("/api/voice/log", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionId: this.sessionId, entries }),
    }).catch(() => {});
    if (final) console.info(`[VoiceLog ${this.sessionId}] flushed`);
  }
}

function clip(value) {
  const text = String(value ?? "");
  return text.length > 400 ? `${text.slice(0, 400)}…[${text.length} chars]` : text;
}

function redact(value, depth = 0) {
  if (depth > 4) return "[depth]";
  if (typeof value === "string") return clip(value);
  if (Array.isArray(value)) return value.slice(0, 50).map((item) => redact(item, depth + 1));
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, nested] of Object.entries(value)) out[key] = redact(nested, depth + 1);
    return out;
  }
  return value;
}

function redactEvent(event) {
  const type = event.type || "";
  if (type === "response.output_audio.delta" || type === "response.audio.delta" || type === "input_audio_buffer.append") {
    const copy = { ...event };
    for (const key of ["delta", "audio"]) {
      if (typeof copy[key] === "string") {
        const bytes = Math.floor((copy[key].length * 3) / 4);
        copy[key] = null;
        copy.bytes = bytes;
      }
    }
    return redact(copy);
  }
  return redact(event);
}

function voiceInstructions(memories, sessionFacts) {
  let text = VOICE_INSTRUCTIONS;
  const longTerm = memories.slice(0, 12);
  text += longTerm.length
    ? `\nKnown family memories from earlier sessions:\n${longTerm.map((item) => `- ${item}`).join("\n")}`
    : "\nNo prior family memories are on file yet.";
  if (sessionFacts.length) {
    text += `\nFacts the speaker already shared in this live conversation. Use these if they ask you to recall:\n${sessionFacts.slice(-12).map((item) => `- ${item}`).join("\n")}`;
  }
  return text;
}

function pcm16FromFloat(samples) {
  const bytes = new Uint8Array(samples.length * 2);
  const view = new DataView(bytes.buffer);
  for (let i = 0; i < samples.length; i += 1) {
    const sample = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(i * 2, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
  }
  return bytes;
}

function resample(input, fromRate, toRate) {
  if (fromRate === toRate) return input;
  const outLength = Math.max(1, Math.round(input.length * toRate / fromRate));
  const out = new Float32Array(outLength);
  const ratio = fromRate / toRate;
  for (let i = 0; i < outLength; i += 1) {
    const position = i * ratio;
    const index = Math.floor(position);
    const next = Math.min(index + 1, input.length - 1);
    const mix = position - index;
    out[i] = input[index] * (1 - mix) + input[next] * mix;
  }
  return out;
}

function rmsOf(samples) {
  if (!samples.length) return 0;
  let sum = 0;
  for (const sample of samples) sum += sample * sample;
  return Math.sqrt(sum / samples.length);
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function base64ToBytes(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

class VoiceSession {
  constructor() {
    this.phase = "idle";
    this.sessionId = "";
    this.onChange = () => {};
  }

  get isLive() {
    return this.phase !== "idle";
  }

  async start(nextThreadId, openingText = "") {
    if (this.phase !== "idle") return;
    this.threadId = nextThreadId;
    this.sessionId = crypto.randomUUID().replaceAll("-", "").slice(0, 8).toLowerCase();
    this.logger = new VoiceLogger(this.sessionId);
    this.socket = null;
    this.socketClosed = false;
    this.socketOpen = false;
    this.sessionReady = false;
    this.acceptMic = false;
    this.responseActive = false;
    this.awaitingResponse = false;
    this.didConfigure = false;
    this.didGreet = false;
    this.pendingAudio = [];
    this.queuedUserText = openingText.trim() || null;
    this.currentUserItemId = null;
    this.currentUserText = "";
    this.sessionFacts = [];
    this.seedMemories = [];
    this.persisted = new Set();
    this.audioIn = { chunks: 0, bytes: 0, rmsMax: 0, rmsSum: 0, at: performance.now() };
    this.outDeltas = 0;
    this.outBytes = 0;
    this.firstDeltaLogged = false;
    this.responseCreatedAt = 0;
    this.speechStoppedAt = 0;
    this.pendingInstructions = VOICE_INSTRUCTIONS;
    this.assistantText = "";
    this.connectStarted = performance.now();
    this.setPhase("connecting");
    this.logger.log("start", { url: "wss://api.x.ai/v1/realtime?model=grok-voice-latest", target_rate: SAMPLE_RATE });
    try {
      await this.connect();
    } catch (error) {
      this.fail("start", error.message || String(error));
    }
  }

  stop() {
    if (!this.isLive) return;
    this.logger?.log("stop", { by: "client", phase: this.phase });
    this.tearDown();
  }

  sendTypedText(text) {
    const trimmed = text.trim();
    if (!this.isLive || !trimmed) return;
    addLine("You", trimmed);
    if (!this.sessionReady || this.responseActive || this.awaitingResponse) {
      this.queuedUserText = trimmed;
      if (this.responseActive) this.sendJSON({ type: "response.cancel" });
      return;
    }
    this.deliverUserText(trimmed);
  }

  async connect() {
    const tokenStarted = performance.now();
    const tokenResponse = await fetch("/api/token", { method: "POST" });
    const tokenBody = await tokenResponse.json();
    if (!tokenResponse.ok || !tokenBody.value) {
      this.fail("token", tokenBody.error || `HTTP ${tokenResponse.status}`, Math.round(performance.now() - tokenStarted));
      return;
    }
    this.logger.log("token.ok", { ms: Math.round(performance.now() - tokenStarted) });

    const micStarted = performance.now();
    this.audio = new AudioContext();
    await this.audio.resume();
    await this.audio.audioWorklet.addModule("/audio-worklet.js");
    this.player = new PcmPlayer(this.audio);
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    const source = this.audio.createMediaStreamSource(this.stream);
    this.capture = new AudioWorkletNode(this.audio, "loom-capture");
    this.floatPending = new Float32Array(0);
    this.capture.port.onmessage = (event) => this.enqueueFloat(event.data);
    source.connect(this.capture);
    this.logger.log("mic.ok", { ms: Math.round(performance.now() - micStarted), label: "default" });
    this.logger.log("env", { mic_rate: this.audio.sampleRate, target_rate: SAMPLE_RATE, ua: navigator.userAgent });

    const recalled = await fetch("/api/memories/recall", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: "", threadId: this.threadId }),
    }).then((response) => response.json()).catch(() => ({ memories: [] }));
    this.seedMemories = recalled.memories || [];
    this.pendingInstructions = voiceInstructions(this.seedMemories, []);

    this.logger.log("ws.connecting", {});
    const socket = new WebSocket(
      "wss://api.x.ai/v1/realtime?model=grok-voice-latest",
      [`xai-client-secret.${tokenBody.value}`],
    );
    this.socket = socket;
    socket.addEventListener("message", (event) => this.onSocketMessage(event));
    socket.addEventListener("close", () => {
      if (!this.socketClosed) this.fail("ws", "Voice connection closed.");
    });
    socket.addEventListener("error", () => {
      if (!this.socketClosed) this.fail("ws", "Voice connection failed.");
    });
  }

  enqueueFloat(frame) {
    if (this.socketClosed || !this.audio) return;
    const merged = new Float32Array(this.floatPending.length + frame.length);
    merged.set(this.floatPending, 0);
    merged.set(frame, this.floatPending.length);
    const windowSize = Math.round(this.audio.sampleRate * 0.1);
    let offset = 0;
    while (merged.length - offset >= windowSize) {
      const slice = merged.subarray(offset, offset + windowSize);
      const pcm = pcm16FromFloat(resample(slice, this.audio.sampleRate, SAMPLE_RATE));
      this.enqueueMic(pcm, rmsOf(slice));
      offset += windowSize;
    }
    this.floatPending = merged.subarray(offset);
  }

  enqueueMic(bytes, rms) {
    this.audioIn.chunks += 1;
    this.audioIn.bytes += bytes.length;
    this.audioIn.rmsMax = Math.max(this.audioIn.rmsMax, rms);
    this.audioIn.rmsSum += rms;
    if (performance.now() - this.audioIn.at >= 2000) {
      this.logger?.log("audio.in", {
        chunks: this.audioIn.chunks,
        bytes: this.audioIn.bytes,
        rms_max: this.audioIn.rmsMax,
        rms_avg: this.audioIn.chunks ? this.audioIn.rmsSum / this.audioIn.chunks : 0,
        pending: this.pendingAudio.length,
        phase: this.phase,
      });
      this.audioIn = { chunks: 0, bytes: 0, rmsMax: 0, rmsSum: 0, at: performance.now() };
    }
    if (!this.acceptMic || !this.socketOpen) {
      if (this.pendingAudio.length >= 200) this.pendingAudio.shift();
      this.pendingAudio.push(bytes);
      return;
    }
    this.sendAudio(bytes);
  }

  flushPendingAudio() {
    if (!this.acceptMic || !this.socketOpen || !this.pendingAudio.length) return;
    this.logger?.log("audio.flush", { chunks: this.pendingAudio.length });
    for (const chunk of this.pendingAudio) this.sendAudio(chunk);
    this.pendingAudio = [];
  }

  sendAudio(bytes) {
    this.sendJSON({ type: "input_audio_buffer.append", audio: bytesToBase64(bytes) }, false);
  }

  sendJSON(object, logClient = true) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    if (logClient) this.logger?.client(object);
    this.socket.send(JSON.stringify(object));
  }

  sendSessionUpdate(instructions) {
    this.sendJSON({
      type: "session.update",
      session: {
        voice: "eve",
        instructions,
        turn_detection: { type: "server_vad", silence_duration_ms: 1200 },
        reasoning: { effort: "none" },
        audio: {
          input: {
            format: { type: "audio/pcm", rate: SAMPLE_RATE },
            transcription: { model: "grok-transcribe" },
          },
          output: { format: { type: "audio/pcm", rate: SAMPLE_RATE } },
        },
      },
    });
  }

  updateInstructionsOnly(instructions) {
    this.sendJSON({
      type: "session.update",
      session: {
        instructions,
      },
    });
  }

  onSocketMessage(event) {
    if (this.socketClosed) return;
    if (typeof event.data !== "string") {
      event.data.arrayBuffer?.().then((buffer) => {
        if (!this.socketClosed) this.player?.play(new Uint8Array(buffer));
      });
      return;
    }
    let object;
    try {
      object = JSON.parse(event.data);
    } catch {
      return;
    }
    const type = object.type || "";
    if (type === "response.output_audio.delta" || type === "response.audio.delta") {
      const b64 = object.delta || object.audio || "";
      if (b64) {
        const pcm = base64ToBytes(b64);
        if (!this.firstDeltaLogged) {
          this.firstDeltaLogged = true;
          this.logger?.log("audio.out.first", {
            response_id: object.response_id || "",
            bytes: pcm.length,
            since_response_created_ms: this.responseCreatedAt ? Math.round(performance.now() - this.responseCreatedAt) : 0,
            since_speech_stopped_ms: this.speechStoppedAt ? Math.round(performance.now() - this.speechStoppedAt) : 0,
          });
        }
        this.outDeltas += 1;
        this.outBytes += pcm.length;
        this.player?.play(pcm);
      }
      this.setPhase("speaking");
      return;
    }

    this.logger?.server({ ...object, phase: this.phase });
    this.markSocketOpen();

    if (type === "session.created") {
      this.configureIfNeeded();
      if (this.phase === "connecting") this.setPhase("listening");
    } else if (type === "session.updated") {
      const becameReady = !this.sessionReady;
      this.sessionReady = true;
      if (becameReady) {
        if (this.queuedUserText) {
          const text = this.queuedUserText;
          this.queuedUserText = null;
          this.didGreet = true;
          this.deliverUserText(text);
        } else {
          this.greet();
        }
      }
      if (this.phase === "connecting") this.setPhase("listening");
    } else if (type === "input_audio_buffer.speech_started") {
      this.player?.stop();
      this.logger?.log("play.stop", { reason: "barge-in", dropped_ms: 0 });
      if (this.responseActive || this.awaitingResponse) {
        this.responseActive = false;
        this.awaitingResponse = false;
        this.sendJSON({ type: "response.cancel" });
      }
      this.setPhase("listening");
    } else if (type === "input_audio_buffer.speech_stopped") {
      this.speechStoppedAt = performance.now();
      this.setPhase("thinking");
    } else if (type === "input_audio_buffer.committed") {
      this.currentUserItemId = object.item_id || null;
      this.currentUserText = "";
      finishStreaming();
      addLine("You", "…", true);
    } else if (type === "conversation.item.input_audio_transcription.updated" || type === "conversation.item.input_audio_transcription.completed") {
      const text = object.transcript || object.text;
      if (text) {
        this.currentUserText = text;
        updateStreaming("You", text);
      }
    } else if (type === "response.created") {
      this.responseCreatedAt = performance.now();
      this.firstDeltaLogged = false;
      this.outDeltas = 0;
      this.outBytes = 0;
      this.responseActive = true;
      this.awaitingResponse = false;
      this.setPhase("thinking");
    } else if (type === "response.output_audio_transcript.delta") {
      if (object.delta) updateStreaming("Loomie", (this.assistantText = (this.assistantText || "") + object.delta));
      this.setPhase("speaking");
    } else if (type === "response.output_audio_transcript.done") {
      if (object.transcript) {
        this.assistantText = object.transcript;
        updateStreaming("Loomie", object.transcript);
      }
    } else if (type === "response.done") {
      this.logger?.log("audio.out", {
        response_id: object.response_id || "",
        status: object.response?.status || "completed",
        deltas: this.outDeltas,
        bytes: this.outBytes,
      });
      this.responseActive = false;
      this.awaitingResponse = false;
      this.persistUserTurn();
      finishStreaming();
      this.assistantText = "";
      if (this.queuedUserText) {
        const text = this.queuedUserText;
        this.queuedUserText = null;
        this.deliverUserText(text);
      } else {
        this.openMic();
        this.setPhase("listening");
      }
    } else if (type === "error") {
      const detail = object.error?.message || object.message || "Voice session error";
      this.handleServerError(detail);
    }
  }

  markSocketOpen() {
    if (this.socketOpen) return;
    this.socketOpen = true;
    this.logger?.log("ws.open", { ms: Math.round(performance.now() - this.connectStarted) });
    this.configureIfNeeded();
    if (this.phase === "connecting") this.setPhase("listening");
  }

  configureIfNeeded() {
    if (this.didConfigure) return;
    this.didConfigure = true;
    this.sendSessionUpdate(this.pendingInstructions);
  }

  greet() {
    if (this.didGreet) return;
    this.didGreet = true;
    this.awaitingResponse = true;
    this.sendJSON({
      type: "conversation.item.create",
      item: {
        type: "force_message",
        role: "assistant",
        interruptible: true,
        content: [{ type: "output_text", text: "Hi, I'm Loomie. It's so nice to hear from you." }],
      },
    });
  }

  deliverUserText(text) {
    this.currentUserItemId = crypto.randomUUID();
    this.currentUserText = text;
    this.awaitingResponse = true;
    this.sendJSON({
      type: "conversation.item.create",
      item: { type: "message", role: "user", content: [{ type: "input_text", text }] },
    });
    this.sendJSON({ type: "response.create" });
  }

  openMic() {
    if (!this.sessionReady || this.acceptMic) return;
    this.acceptMic = true;
    this.flushPendingAudio();
  }

  handleServerError(detail) {
    this.logger?.error("server", detail);
    const lowered = detail.toLowerCase();
    if (lowered.includes("active response") || lowered.includes("in progress")) return;
    const recoverable = lowered.includes("buffer too small") || lowered.includes("already");
    if (!recoverable) addLine("Error", detail);
    this.awaitingResponse = false;
    if (this.responseActive) return;
    if (this.queuedUserText) {
      const text = this.queuedUserText;
      this.queuedUserText = null;
      this.deliverUserText(text);
      return;
    }
    this.openMic();
  }

  persistUserTurn() {
    const item = this.currentUserItemId || this.currentUserText;
    if (!item || this.persisted.has(item)) return;
    this.persisted.add(item);
    this.absorbFact(this.currentUserText);
  }

  async absorbFact(text) {
    const utterance = text.trim();
    if (!utterance || this.sessionFacts.some((fact) => fact.toLowerCase() === utterance.toLowerCase())) return;
    const response = await fetch("/api/memories/remember", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: utterance, threadId: this.threadId }),
    }).then((result) => result.json()).catch(() => ({ stored: false }));
    if (!response.stored) return;
    this.sessionFacts.push(utterance);
    this.logger?.log("memory.store", { stored: Boolean(response.stored), facts: this.sessionFacts.length });
    const recalled = await fetch("/api/memories/recall", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: utterance, threadId: this.threadId }),
    }).then((result) => result.json()).catch(() => ({ memories: [] }));
    if (recalled.memories?.length) this.seedMemories = recalled.memories;
    this.pendingInstructions = voiceInstructions(this.seedMemories, this.sessionFacts);
    this.updateInstructionsOnly(this.pendingInstructions);
  }

  setPhase(next) {
    if (this.phase === next) return;
    this.phase = next;
    this.logger?.log("phase", { phase: next });
    this.onChange();
  }

  fail(where, message, ms) {
    if (this.socketClosed) return;
    this.logger?.error(where, message);
    if (ms != null) this.logger?.log("error", { where, ms });
    addLine("Error", `${message} (voice session ${this.sessionId})`);
    this.tearDown();
  }

  tearDown() {
    if (this.socketClosed) return;
    this.socketClosed = true;
    this.logger?.log("ws.close", { code: 1000, reason: "client stop", wasClean: true, by: "client" });
    this.socket?.close();
    this.socket = null;
    this.capture?.disconnect();
    this.stream?.getTracks().forEach((track) => track.stop());
    this.player?.stop();
    this.audio?.close();
    this.acceptMic = false;
    this.sessionReady = false;
    this.socketOpen = false;
    this.logger?.close();
    this.logger = null;
    this.phase = "idle";
    this.onChange();
  }
}

class PcmPlayer {
  constructor(audio) {
    this.audio = audio;
    this.nextTime = 0;
    this.sources = [];
    this.odd = null;
  }

  play(bytes) {
    let data = bytes;
    if (this.odd != null) {
      const merged = new Uint8Array(data.length + 1);
      merged[0] = this.odd;
      merged.set(data, 1);
      data = merged;
      this.odd = null;
    }
    if (data.length % 2 === 1) {
      this.odd = data[data.length - 1];
      data = data.subarray(0, data.length - 1);
    }
    if (!data.length) return;
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const buffer = this.audio.createBuffer(1, data.length / 2, SAMPLE_RATE);
    const channel = buffer.getChannelData(0);
    for (let i = 0; i < channel.length; i += 1) channel[i] = view.getInt16(i * 2, true) / 32768;
    const source = this.audio.createBufferSource();
    source.buffer = buffer;
    source.connect(this.audio.destination);
    const now = this.audio.currentTime;
    if (this.nextTime < now) this.nextTime = now + 0.02;
    source.start(this.nextTime);
    this.nextTime += buffer.duration;
    this.sources.push(source);
    source.onended = () => {
      const idx = this.sources.indexOf(source);
      if (idx !== -1) this.sources.splice(idx, 1);
    };
  }

  stop() {
    for (const source of this.sources) {
      try { source.stop(); } catch { /* already ended */ }
    }
    this.sources = [];
    this.nextTime = 0;
    this.odd = null;
  }
}

function startVoice(openingText) {
  if (!openingText) {
    addLine("Test", "Loomie will say hello, then listen. Just talk — she answers when you pause. Tap the waveform again to hang up. Headphones help.");
  }
  voice.start(threadId, openingText || "");
}

actionEl.addEventListener("click", () => {
  const text = draftEl.value.trim();
  if (text) {
    draftEl.value = "";
    if (voice.isLive) voice.sendTypedText(text);
    else {
      addLine("You", text);
      startVoice(text);
    }
  } else if (voice.isLive) {
    voice.stop();
  } else {
    startVoice("");
  }
  render();
});

draftEl.addEventListener("input", render);

memoryTestEl.addEventListener("click", async () => {
  busy = true;
  render();
  threadId = crypto.randomUUID();
  addLine("Test", "Starting memory recall test on a fresh thread. Prompt 2 will not repeat the story.");
  const story = "In 1970, I worked at a print shop in Chicago with my brother Arthur.";
  const probe = "Where did I work and who was with me?";
  addLine("You", story);
  try {
    const first = await postChat(story);
    addLine("Loomie", first);
  } catch (error) {
    addLine("Error", error.message);
    addLine("Test", "Memory test aborted: first turn failed.");
    busy = false;
    render();
    return;
  }
  await new Promise((resolve) => setTimeout(resolve, 1200));
  addLine("You", probe);
  let second = "";
  try {
    second = await postChat(probe);
    addLine("Loomie", second);
  } catch (error) {
    addLine("Error", error.message);
    addLine("Test", "Memory test aborted: recall turn failed.");
    busy = false;
    render();
    return;
  }
  const haystack = second.toLowerCase();
  const recalledPlace = haystack.includes("print") || haystack.includes("chicago");
  const recalledPerson = haystack.includes("arthur");
  const leakedStory = probe.toLowerCase().includes("print") || probe.toLowerCase().includes("arthur");
  addLine("Test", recalledPlace && recalledPerson && !leakedStory
    ? "Recalled print shop / Chicago and Arthur from Backboard memory without repeating them in prompt 2."
    : `Recall check failed. place=${recalledPlace} person=${recalledPerson} leakedInPrompt2=${leakedStory}`);
  busy = false;
  render();
});

storyTestEl.addEventListener("click", async () => {
  busy = true;
  render();
  addLine("Test", "Cross-session test. Conversation 1 will be wrapped up, then a new thread will ask about the car project.");
  try {
    const response = await fetch("/api/story/cross-session-test", { method: "POST" });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
    addLine("Loomie", body.reply || "");
    addLine("Test", body.ok
      ? `Recalled the 1968 car restoration with Uncle Bob on a new thread. Saved “${body.title}”.`
      : `Cross-session recall failed. year=${body.year} person=${body.person} project=${body.project}`);
  } catch (error) {
    addLine("Error", error.message);
    addLine("Test", "Cross-session test aborted.");
  }
  busy = false;
  render();
});

wrapUpStoryEl?.addEventListener("click", async () => {
  busy = true;
  if (voice.isLive) voice.stop();
  render();
  const transcript = messages
    .filter((l) => (l.sender === "You" || l.sender === "Loomie") && l.text && l.text !== "…")
    .map((l) => `${l.sender === "You" ? "Elder" : "Loomie"}: ${l.text}`)
    .join("\n");
  try {
    const response = await fetch("/api/story/wrap-up", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ transcript }),
    });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
    savedArtifact = {
      ...body.artifact,
      authorName: body.author_name || body.artifact?.authorName || "Joseph Clarke",
      mongo_saved: body.mongo_saved,
      story_id: body.story_id,
      spark_id: body.spark_id,
    };
    threadId = crypto.randomUUID();
    messages.length = 0;
    if (body.is_new_member && body.new_member) {
      addLine("Test", `🌱 Grok Archive Agent created NEW family member in Atlas: ${body.author_name} (${body.new_member._id}, Generation ${body.new_member.generation_tier})`);
    }
    const mongoMsg = body.mongo_saved
      ? `🍃 Saved to MongoDB Atlas (Story ID: ${body.story_id}${body.spark_id ? `, Spark: ${body.spark_id}` : ""}).`
      : "";
    addLine("Test", `Saved “${savedArtifact.title}” by ${body.author_name || "Elder"} to archives. ${mongoMsg} This is a new conversation.`);
  } catch (error) {
    addLine("Error", error.message || String(error));
  }
  busy = false;
  render();
});

mongoTestEl?.addEventListener("click", async () => {
  busy = true;
  render();
  addLine("Test", "Verifying MongoDB Atlas connection and live document persistence…");
  try {
    const response = await fetch("/api/story/test-mongo", { method: "POST" });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
    addLine("Test", body.saved
      ? `🍃 MongoDB Atlas Verified! Inserted test story “${body.title}” (ID: ${body.story_id}). Total family stories in Atlas: ${body.total_stories}.`
      : "MongoDB verification failed to confirm saved document.");
  } catch (error) {
    addLine("Error", error.message || String(error));
  }
  busy = false;
  render();
});

searchConnectionsEl?.addEventListener("click", async () => {
  busy = true;
  render();
  const query = "Who in our family has creative crafts, electronics, or woodworking hobbies across generations?";
  addLine("Test", `🔍 Grok Archive Agent searching connections across family archives: "${query}"…`);
  try {
    const response = await fetch("/api/archive/search-connections", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
    });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
    addLine("Loomie", `✨ ${body.headline}\n\n${body.deep_connection}\n\nConnected Members: ${body.connected_members?.join(", ")}`);
    if (body.conversation_starters?.length) {
      addLine("Test", `Conversation Starters:\n• ${body.conversation_starters.join("\n• ")}`);
    }
  } catch (error) {
    addLine("Error", error.message || String(error));
  }
  busy = false;
  render();
});

async function loadAndRenderCorkboard() {
  try {
    const res = await fetch("/api/tree");
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "Failed to load tree layout");
    corkboardSvgEl.innerHTML = "";
    corkboardCardsEl.innerHTML = "";

    corkboardSvgEl.setAttribute("viewBox", `0 0 ${data.canvas_width} ${data.canvas_height}`);
    corkboardSvgEl.style.width = `${data.canvas_width}px`;
    corkboardSvgEl.style.height = `${data.canvas_height}px`;

    // Render Generation Tier Divider Guides
    for (const tier of (data.generation_tiers || [])) {
      const guide = document.createElement("div");
      guide.className = "corkboard-tier-guide";
      guide.style.top = `${tier.y}px`;
      guide.textContent = tier.title;
      corkboardCardsEl.appendChild(guide);
    }

    // Render Red Twine Strings
    for (const str of (data.strings || [])) {
      const midX = (str.from_x + str.to_x) / 2;
      const midY = (str.from_y + str.to_y) / 2 + (str.sag_pixels || 16);
      const d = `M ${str.from_x} ${str.from_y} Q ${midX} ${midY} ${str.to_x} ${str.to_y}`;
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d);
      path.setAttribute("stroke", str.color || "#d63031");
      path.setAttribute("stroke-width", str.type === "spouse" ? "2.8" : "2.2");
      path.setAttribute("fill", "none");
      path.setAttribute("stroke-linecap", "round");
      path.style.filter = "drop-shadow(1px 2px 3px rgba(0,0,0,0.35))";
      corkboardSvgEl.appendChild(path);
    }

    // Render Evidence Cards
    for (const node of (data.nodes || [])) {
      const card = document.createElement("div");
      card.className = "corkboard-card";
      card.style.left = `${node.x}px`;
      card.style.top = `${node.y}px`;
      card.style.transform = `rotate(${node.rotation_deg}deg)`;

      const pin = document.createElement("div");
      pin.className = "corkboard-pin";
      pin.style.background = node.pin_color || "#e84118";

      const photo = document.createElement("div");
      photo.className = "corkboard-photo";
      if (node.avatar_url) {
        const img = document.createElement("img");
        img.src = node.avatar_url;
        img.alt = node.name;
        img.onerror = () => {
          photo.innerHTML = `<span class="initials">${escapeHtml(node.name.slice(0, 2))}</span>`;
        };
        photo.appendChild(img);
      } else {
        photo.innerHTML = `<span class="initials">${escapeHtml(node.name.slice(0, 2))}</span>`;
      }

      const info = document.createElement("div");
      info.className = "corkboard-info";
      info.innerHTML = `
        <div class="corkboard-name">${escapeHtml(node.name)}</div>
        <div class="corkboard-gen">Gen ${node.generation_tier}${node.birth_year ? ` · b. ${node.birth_year}` : ""}</div>
      `;

      card.appendChild(pin);
      card.appendChild(photo);
      card.appendChild(info);
      corkboardCardsEl.appendChild(card);
    }

    corkboardOverlayEl.hidden = false;
  } catch (err) {
    addLine("Error", `Corkboard layout error: ${err.message}`);
  }
}

viewCorkboardEl?.addEventListener("click", () => {
  loadAndRenderCorkboard();
});

corkboardRefreshEl?.addEventListener("click", () => {
  loadAndRenderCorkboard();
});

corkboardCloseEl?.addEventListener("click", () => {
  if (corkboardOverlayEl) corkboardOverlayEl.hidden = true;
});

newThreadEl?.addEventListener("click", () => {
  if (voice.isLive) voice.stop();
  threadId = crypto.randomUUID();
  draftEl.value = "";
  messages.length = 0;
  addLine("Test", "New conversation. Saved stories stay in Backboard.");
  render();
});

async function postChat(text) {
  const response = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, threadId }),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
  return body.reply;
}

voice = new VoiceSession();
voice.onChange = render;

fetch("/api/health")
  .then((response) => response.json())
  .then((health) => {
    if (!health.hasXai) {
      addLine("Error", "XAI_API_KEY is not set. Add it to middleware/.env, then restart the preview.");
    }
    if (!health.hasBackboard) {
      addLine("Error", "BACKBOARD_API_KEY is not set. Memory recall will be empty until it is.");
    }
    if (!health.hasMongo) {
      addLine("Error", "MONGODB_URI is not set. MongoDB Atlas persistence will be disabled.");
    }
  })
  .catch(() => addLine("Error", "Preview server is not responding."));

render();
