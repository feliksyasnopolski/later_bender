import type { Request } from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

type RawBodyRequest = Request & { rawBody?: Buffer };

const requestSnapshot = z.object({
  method: z.string(),
  url: z.string(),
  originalUrl: z.string(),
  httpVersion: z.string(),
  headers: z.record(z.string(), z.union([z.string(), z.array(z.string())])),
  headersDistinct: z.record(z.string(), z.array(z.string())),
  rawHeaders: z.array(z.string()),
  trailers: z.record(z.string(), z.string()),
  trailersDistinct: z.record(z.string(), z.array(z.string())),
  rawTrailers: z.array(z.string()),
  headerRepresentationNote: z.string(),
  bodyByteLength: z.number().int().nonnegative(),
  bodyUtf8: z.string(),
  bodyBase64: z.string(),
  parsedBody: z.any(),
  transport: z.object({
    ip: z.string().nullable(),
    ips: z.array(z.string()),
    protocol: z.string(),
    secure: z.boolean(),
    socketRemoteAddress: z.string().nullable(),
    socketRemotePort: z.number().nullable(),
    socketLocalAddress: z.string().nullable(),
    socketEncrypted: z.boolean(),
  }),
  authInfo: z
    .object({
      token: z.string(),
      clientId: z.string(),
      scopes: z.array(z.string()),
      expiresAt: z.number(),
      extra: z.record(z.string(), z.any()).optional(),
    })
    .nullable(),
});

/** Temporary, request-scoped observation probe. Never logs or persists request data. */
export function registerRequestDiagnosticTool(
  server: McpServer,
  request: RawBodyRequest,
): void {
  server.registerTool(
    "__TEMP_mcp_request_diagnostic",
    {
      title: "TEMP MCP request diagnostic",
      description:
        "TEMPORARY acceptance probe. Returns the inbound HTTP request associated with this tool call, including every header value without redaction (including Authorization), Node's raw header names/order, distinct and parsed header maps, trailers, the raw request-body bytes as UTF-8 and base64, parsed JSON, transport metadata, and parsed auth info. Nothing is persisted. The snapshot covers only the HTTP request that invokes this tool, not earlier initialization requests. Header values are returned exactly as exposed by Node's HTTP parser; Node does not expose the original wire-format whitespace/CRLF bytes for headers.",
      inputSchema: {},
      outputSchema: { request: requestSnapshot },
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    () => {
      const raw = request.rawBody ?? Buffer.alloc(0);
      const auth = (
        request as Request & {
          auth?: {
            token: string;
            clientId: string;
            scopes: string[];
            expiresAt: number;
            extra?: Record<string, unknown>;
          };
        }
      ).auth;
      const headers = Object.fromEntries(
        Object.entries(request.headers).filter(
          (entry): entry is [string, string | string[]] =>
            entry[1] !== undefined,
        ),
      );
      const snapshot = {
        method: request.method,
        url: request.url,
        originalUrl: request.originalUrl,
        httpVersion: request.httpVersion,
        headers,
        headersDistinct: request.headersDistinct,
        rawHeaders: request.rawHeaders,
        trailers: request.trailers,
        trailersDistinct: request.trailersDistinct,
        rawTrailers: request.rawTrailers,
        headerRepresentationNote:
          "rawHeaders preserves the names, order, and values exposed by Node's HTTP parser, but Node does not expose original header-line whitespace or CRLF bytes. Body base64 is the exact byte sequence captured before JSON parsing.",
        bodyByteLength: raw.byteLength,
        bodyUtf8: raw.toString("utf8"),
        bodyBase64: raw.toString("base64"),
        parsedBody: request.body ?? null,
        transport: {
          ip: request.ip ?? null,
          ips: request.ips,
          protocol: request.protocol,
          secure: request.secure,
          socketRemoteAddress: request.socket.remoteAddress ?? null,
          socketRemotePort: request.socket.remotePort ?? null,
          socketLocalAddress: request.socket.localAddress ?? null,
          socketEncrypted: Boolean(
            (request.socket as typeof request.socket & { encrypted?: boolean })
              .encrypted,
          ),
        },
        authInfo: auth
          ? {
              token: auth.token,
              clientId: auth.clientId,
              scopes: auth.scopes,
              expiresAt: auth.expiresAt,
              extra: auth.extra,
            }
          : null,
      };
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({ request: snapshot }),
          },
        ],
        structuredContent: { request: snapshot },
      };
    },
  );
}
