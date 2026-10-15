import { DurableObject } from "cloudflare:workers";

// const ROOM_PATH = /^\/ws\/([A-HJ-NP-Z2-9]{6})\/(create|join)$/i;
const ROOM_PATH = /^\/ws\/(\d{6})\/(create|join)$/;

export class MyDurableObject extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("A WebSocket connection is required.", { status: 426 });
    }

    const match = new URL(request.url).pathname.match(ROOM_PATH);
    if (!match) {
      return new Response("Invalid room path.", { status: 400 });
    }

    const roomCode = match[1].toUpperCase();
    const action = match[2].toLowerCase();
    const sockets = this.ctx
      .getWebSockets()
      .filter((socket) => socket.readyState === WebSocket.OPEN);

    if (action === "create") {
      if (sockets.length > 0) {
        return new Response("That room code is already in use.", { status: 409 });
      }

      return this.acceptPlayer(roomCode, 1, "room_created");
    }

    if (sockets.length === 0) {
      return new Response("Room not found.", { status: 404 });
    }

    if (sockets.length >= 2) {
      return new Response("Room is full.", { status: 409 });
    }

    const host = sockets[0];
    if (!host) {
      return new Response("Room not found.", { status: 404 });
    }

    const response = this.acceptPlayer(roomCode, 2, "room_joined");
    this.sendJson(host, { type: "opponent_joined" });
    return response;
  }

  webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): void {
    if (typeof message !== "string" || message.length > 16_384) {
      ws.close(1009, "Invalid or oversized message.");
      return;
    }

    let packet: unknown;
    try {
      packet = JSON.parse(message);
    } catch {
      this.sendJson(ws, { type: "error", message: "Invalid JSON." });
      return;
    }

    if (
      typeof packet !== "object" ||
      packet === null ||
      Array.isArray(packet) ||
      !("type" in packet) ||
      packet.type !== "game_message" ||
      !("payload" in packet)
    ) {
      this.sendJson(ws, { type: "error", message: "Expected a game_message." });
      return;
    }

    const sender = ws.deserializeAttachment() as { player?: number } | null;

    for (const opponent of this.ctx.getWebSockets()) {
      if (opponent !== ws && opponent.readyState === WebSocket.OPEN) {
        this.sendJson(opponent, {
          type: "game_message",
          from_player: sender?.player ?? null,
          payload: packet.payload
        });
      }
    }
  }

  webSocketClose(
    ws: WebSocket,
    _code: number,
    _reason: string,
    _wasClean: boolean
  ): void {
    for (const opponent of this.ctx.getWebSockets()) {
      if (opponent !== ws && opponent.readyState === WebSocket.OPEN) {
        this.sendJson(opponent, { type: "opponent_disconnected" });
        opponent.close(4001, "Opponent disconnected.");
      }
    }
  }

  private acceptPlayer(
    roomCode: string,
    player: number,
    messageType: string
  ): Response {
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];

    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ player, roomCode });
    this.sendJson(server, { type: messageType, code: roomCode });

    return new Response(null, { status: 101, webSocket: client });
  }

  private sendJson(socket: WebSocket, message: Record<string, unknown>): void {
    socket.send(JSON.stringify(message));
  }
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/" && request.headers.get("Upgrade") !== "websocket") {
      return new Response("V!s!on room server is ready.");
    }

    const match = url.pathname.match(ROOM_PATH);
    if (!match) {
      return new Response(
        "Use /ws/ROOMCODE/create or /ws/ROOMCODE/join.",
        { status: 404 }
      );
    }

    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("A WebSocket connection is required.", { status: 426 });
    }

    const roomCode = match[1].toUpperCase();
    return env.MY_DURABLE_OBJECT.getByName(roomCode).fetch(request);
  }
} satisfies ExportedHandler<Env>;