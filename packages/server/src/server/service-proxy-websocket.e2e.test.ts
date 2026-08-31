import { once } from "node:events";

import { expect, test } from "vitest";
import { WebSocket, WebSocketServer } from "ws";

import { createTestPaseoDaemon, type TestPaseoDaemon } from "./test-utils/paseo-daemon.js";

async function startEchoWebSocketService(): Promise<{
  port: number;
  server: WebSocketServer;
}> {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  server.on("connection", (socket) => {
    socket.on("message", (message) => socket.send(message));
  });
  await once(server, "listening");

  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("WebSocket service did not expose a TCP address");
  }
  return { port: address.port, server };
}

async function closeWebSocketServer(server: WebSocketServer): Promise<void> {
  for (const socket of server.clients) {
    socket.terminate();
  }
  await new Promise<void>((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

test("a workspace service WebSocket upgrades through the daemon listener", async () => {
  const upstream = await startEchoWebSocketService();
  let daemon: TestPaseoDaemon | null = null;
  let client: WebSocket | null = null;

  try {
    daemon = await createTestPaseoDaemon();
    const route = daemon.daemon.serviceProxy.registerWorkspaceService({
      workspaceId: "workspace-a",
      projectSlug: "project-a",
      branchName: "main",
      scriptName: "wails",
      port: upstream.port,
    });
    client = new WebSocket(`ws://127.0.0.1:${daemon.port}/wails/events/?token=vite-hmr-token`, {
      headers: { host: `${route.hostname}:${daemon.port}` },
    });
    await once(client, "open");
    client.send("hello through Paseo");
    const [message] = await once(client, "message");

    expect(message.toString()).toBe("hello through Paseo");
  } finally {
    client?.terminate();
    try {
      await daemon?.close();
    } finally {
      await closeWebSocketServer(upstream.server);
    }
  }
});

test("the daemon WebSocket still upgrades through the shared dispatcher", async () => {
  const daemon = await createTestPaseoDaemon();
  let client: WebSocket | null = null;

  try {
    client = new WebSocket(`ws://127.0.0.1:${daemon.port}/ws`);
    await once(client, "open");
    expect(client.readyState).toBe(WebSocket.OPEN);
  } finally {
    client?.terminate();
    await daemon.close();
  }
});
