// WebRTC Signaling Server for Rift
import type { ServerWebSocket } from "bun";

// Define types for our WebSocket data
type WebSocketData = { roomId: string };

// Store active clients by roomId and clientId
type Client = { ws: ServerWebSocket<WebSocketData>; id: string; roomId: string };
const rooms = new Map<string, Map<string, Client>>();

// Helper to get or create a room
function getOrCreateRoom(roomId: string): Map<string, Client> {
  if (!rooms.has(roomId)) {
    rooms.set(roomId, new Map());
    console.log(`Room created: ${roomId}`);
  }
  return rooms.get(roomId)!;
}

// Helper to broadcast to all clients in a room except sender
function broadcastToRoom(roomId: string, senderId: string, message: string) {
  const room = rooms.get(roomId);
  if (!room) return;
  
  console.log(`Broadcasting in room ${roomId} from ${senderId}`);
  room.forEach((client, id) => {
    if (id !== senderId) {
      client.ws.send(message);
    }
  });
}

// Start the server
const server = Bun.serve({
  port: 3000,
  fetch(req, server) {
    // Get the client's IP for logging
    const clientIp = req.headers.get("x-forwarded-for") || "unknown";
    console.log(`Connection attempt from ${clientIp}`);
    
    // Extract roomId from URL path
    const url = new URL(req.url);
    const roomId = url.pathname.slice(1) || "default";
    
    // Upgrade the request to a WebSocket
    if (server.upgrade(req, { data: { roomId } })) {
      return; // Successfully upgraded
    }
    
    // Return a simple status page if not a WebSocket request
    return new Response(`Rift Signaling Server - Active Rooms: ${rooms.size}`, {
      status: 200,
      headers: { "Content-Type": "text/plain" },
    });
  },
  websocket: {
    open(ws: ServerWebSocket<WebSocketData>) {
      // Generate a unique client ID
      const clientId = crypto.randomUUID();
      const roomId = ws.data.roomId;
      
      // Add client to the room
      const room = getOrCreateRoom(roomId);
      room.set(clientId, { ws, id: clientId, roomId });
      
      console.log(`Client ${clientId} joined room ${roomId}. Room size: ${room.size}`);
      
      // Send the client their ID
      ws.send(JSON.stringify({ type: "connected", clientId }));
      
      // Notify others in the room about the new peer
      broadcastToRoom(roomId, clientId, JSON.stringify({
        type: "peer-joined",
        peerId: clientId,
        timestamp: Date.now()
      }));
    },
    message(ws: ServerWebSocket<WebSocketData>, message: string | Buffer) {
      try {
        // Parse the message
        const data = JSON.parse(message as string);
        const { type, target, sender } = data;
        
        if (!sender) {
          console.error("Message missing sender ID");
          return;
        }
        
        // Find the client's room
        let clientRoom: Map<string, Client> | undefined;
        let roomId: string = "";
        
        // Find which room this client is in
        for (const [id, room] of rooms.entries()) {
          if (room.has(sender)) {
            clientRoom = room;
            roomId = id;
            break;
          }
        }
        
        if (!clientRoom) {
          console.error(`Client ${sender} not found in any room`);
          return;
        }
        
        console.log(`Message from ${sender} in room ${roomId}: ${type}`);
        
        // Handle different message types
        switch (type) {
          case "offer":
          case "answer":
          case "ice-candidate":
            // Direct message to a specific peer
            if (target && clientRoom.has(target)) {
              const targetClient = clientRoom.get(target)!;
              targetClient.ws.send(message as string);
              console.log(`Forwarded ${type} from ${sender} to ${target}`);
            }
            break;
            
          case "broadcast":
            // Broadcast to all peers in the room
            broadcastToRoom(roomId, sender, message as string);
            break;
            
          default:
            console.log(`Unknown message type: ${type}`);
        }
      } catch (error) {
        console.error("Error handling message:", error);
      }
    },
    close(ws: ServerWebSocket<WebSocketData>) {
      // Find and remove the client
      for (const [roomId, room] of rooms.entries()) {
        for (const [clientId, client] of room.entries()) {
          if (client.ws === ws) { // Compare the WebSocket instances
            // Remove client from room
            room.delete(clientId);
            console.log(`Client ${clientId} left room ${roomId}. Room size: ${room.size}`);
            
            // Notify others in the room
            broadcastToRoom(roomId, clientId, JSON.stringify({
              type: "peer-left",
              peerId: clientId,
              timestamp: Date.now()
            }));
            
            // Clean up empty rooms
            if (room.size === 0) {
              rooms.delete(roomId);
              console.log(`Room ${roomId} deleted (empty)`);
            }
            
            return;
          }
        }
      }
    },
    drain(ws: ServerWebSocket<WebSocketData>) {
      console.log(`WebSocket backpressure: ${ws.getBufferedAmount()}`); // Using correct method
    },
  },
});

console.log(`Rift Signaling Server running at http://${server.hostname}:${server.port}`);
