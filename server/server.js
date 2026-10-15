const { WebSocketServer } = require("ws");

const server = new WebSocketServer({ port: 8080 });
const rooms = new Map();

function makeRoomCode() {
  const characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code;

  do {
    code = Array.from(
      { length: 6 },
      () => characters[Math.floor(Math.random() * characters.length)]
    ).join("");
  } while (rooms.has(code));

  return code;
}

function send(socket, message) {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

server.on("connection", (socket) => {
  socket.roomCode = null;

  socket.on("message", (rawMessage) => {
    let message;

    try {
      message = JSON.parse(rawMessage.toString());
    } catch {
      send(socket, { type: "error", message: "Invalid message." });
      return;
    }

    if (message.type === "create_room") {
      if (socket.roomCode) return;

      const code = makeRoomCode();
      rooms.set(code, [socket]);
      socket.roomCode = code;
      send(socket, { type: "room_created", code });
      return;
    }

    if (message.type === "join_room") {
      if (socket.roomCode) return;

      const code = String(message.code || "").toUpperCase().trim();
      const players = rooms.get(code);

      if (!players) {
        send(socket, { type: "error", message: "Room not found." });
        return;
      }

      if (players.length >= 2) {
        send(socket, { type: "error", message: "Room is full." });
        return;
      }

      players.push(socket);
      socket.roomCode = code;

      send(players[0], { type: "opponent_joined" });
      send(players[1], { type: "room_joined", code });
      return;
    }

    if (message.type === "game_message" && socket.roomCode) {
      const players = rooms.get(socket.roomCode) || [];
      const opponent = players.find((player) => player !== socket);

      if (opponent) {
        send(opponent, {
          type: "game_message",
          payload: message.payload
        });
      }
    }
  });

  socket.on("close", () => {
    if (!socket.roomCode) return;

    const players = rooms.get(socket.roomCode) || [];
    const opponent = players.find((player) => player !== socket);

    if (opponent) {
      send(opponent, { type: "opponent_disconnected" });
    }

    rooms.delete(socket.roomCode);
  });
});

console.log("Room server listening on ws://localhost:8080");