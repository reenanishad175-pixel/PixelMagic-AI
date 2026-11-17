import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  try {
    const body = await req.json();
    const task = String(body.task ?? "");
    const action = String(body.action ?? "submit");

    if (action === "gemini_check") {
      return Deno.env.get("GEMINI_API_KEY")
        ? json({ configured: true, note: "API key is configured; model quota and billing are checked during generation." })
        : json({ configured: false, error: "GEMINI_API_KEY is not configured in Supabase secrets." }, 503);
    }

    if (task === "gemini_chat" || task === "gemini_image") {
      const geminiKey = Deno.env.get("GEMINI_API_KEY");
      if (!geminiKey) return json({ error: "Gemini is not configured on the server. Add GEMINI_API_KEY in Supabase Edge Function Secrets." }, 503);
      const prompt = String(body.prompt ?? "").trim();
      if (task === "gemini_chat") {
        const history = Array.isArray(body.history) ? body.history.slice(-10) : [];
        if (!prompt || prompt.length > 8000) return json({ error: "Message must be 1–8000 characters." }, 400);
        const contents = history
          .filter((m: any) => m && (m.role === "user" || m.role === "model") && typeof m.text === "string")
          .map((m: any) => ({ role: m.role, parts: [{ text: m.text.slice(0, 8000) }] }));
        contents.push({ role: "user", parts: [{ text: prompt }] });
        const requestBody = JSON.stringify({ contents, generationConfig: { temperature: 0.6, maxOutputTokens: 1024 } });
        const primaryModel = "gemini-3.8-flash";
        const callModel = async (model: string, timeoutMs = 18000) => {
          const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
            method: "POST",
            headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey },
            body: requestBody,
            signal: AbortSignal.timeout(timeoutMs),
          });
          const raw = await response.text();
          let parsed: any = {};
          try { parsed = raw ? JSON.parse(raw) : {}; } catch { parsed = { error: { message: raw } }; }
          return { response, data: parsed };
        };
        let attempt: { response: Response; data: any } | null = null;
        let lastFailure = "Gemini chat request failed.";
        try {
          attempt = await callModel(primaryModel, 18000);
          if (!attempt.response.ok) lastFailure = attempt.data?.error?.message ?? lastFailure;
        } catch (error) {
          lastFailure = error instanceof Error ? error.message : lastFailure;
        }

        // A single slow/overloaded model must not hold the chat for minutes.
        // Discover models enabled for this key and try at most two fast fallbacks.
        if (!attempt?.response.ok) {
          try {
            const listResponse = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000", {
              headers: { "x-goog-api-key": geminiKey },
              signal: AbortSignal.timeout(7000),
            });
            if (listResponse.ok) {
              const listData = await listResponse.json();
              const available = (Array.isArray(listData?.models) ? listData.models : [])
                .filter((model: any) => {
                  const name = String(model?.name ?? "").replace(/^models\\//, "");
                  const methods = Array.isArray(model?.supportedGenerationMethods) ? model.supportedGenerationMethods : [];
                  return name && name !== primaryModel && name.toLowerCase().includes("flash") &&
                    !/(image|audio|live|embedding|preview|experimental)/i.test(name) &&
                    methods.includes("generateContent");
                })
                .sort((a: any, b: any) => {
                  const an = String(a.name).toLowerCase();
                  const bn = String(b.name).toLowerCase();
                  const ar = an.includes("flash-lite") ? 0 : 1;
                  const br = bn.includes("flash-lite") ? 0 : 1;
                  return ar - br || an.localeCompare(bn);
                });
              for (const model of available.slice(0, 2)) {
                const fallbackName = String(model.name).replace(/^models\\//, "");
                try {
                  const fallbackAttempt = await callModel(fallbackName, 15000);
                  attempt = fallbackAttempt;
                  if (fallbackAttempt.response.ok) break;
                  lastFailure = fallbackAttempt.data?.error?.message ?? lastFailure;
                } catch (error) {
                  lastFailure = error instanceof Error ? error.message : lastFailure;
                }
              }
            }
          } catch (error) {
            lastFailure = error instanceof Error ? error.message : lastFailure;
          }
        }
        if (!attempt?.response.ok) {
          return json({ error: lastFailure }, attempt?.response.status ?? 503);
        }
        const data = attempt.data;
        const text = (data?.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? "").join("").trim();
        if (!text) return json({ error: "Gemini returned an empty response." }, 502);
        return json({ text });
      }

      if (prompt.length < 3 || prompt.length > 2000) return json({ error: "Image prompt must be 3–2000 characters." }, 400);
      const upstream = await fetch("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent", {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { responseModalities: ["IMAGE", "TEXT"] },
        }),
      });
      const data = await upstream.json();
      if (!upstream.ok) return json({ error: data?.error?.message ?? "Gemini image generation failed." }, upstream.status);
      const parts = data?.candidates?.[0]?.content?.parts ?? [];
      const imagePart = parts.find((part: any) => part?.inlineData?.data);
      if (!imagePart) {
        const explanation = parts.map((part: any) => part.text ?? "").join(" ").trim();
        return json({ error: explanation || "Gemini did not return an image. Check model access and API billing/limits." }, 502);
      }
      return json({ image_base64: imagePart.inlineData.data, mime_type: imagePart.inlineData.mimeType ?? "image/png" });
    }

    const key = Deno.env.get("FAL_KEY");
    if (!key) return json({ error: "AI service is not configured on the server." }, 503);
    const prompt = String(body.prompt ?? "").trim();
    const requestId = String(body.request_id ?? "").trim();
    const models: Record<string, string> = {
      image: "fal-ai/flux/schnell",
      image_edit: "fal-ai/flux-pro/kontext",
      video: "fal-ai/kling-video/v2.1/standard/text-to-video",
      image_to_video: "fal-ai/kling-video/v2.1/standard/image-to-video",
    };

    if (action === "status" || action === "result") {
      if (!requestId || !/^[a-zA-Z0-9_-]{8,128}$/.test(requestId)) return json({ error: "Invalid request id." }, 400);
      const model = models[task];
      if (!model) return json({ error: "Unsupported AI task." }, 400);
      const endpoint = action === "status"
        ? `https://queue.fal.run/${model}/requests/${requestId}/status`
        : `https://queue.fal.run/${model}/requests/${requestId}`;
      const upstream = await fetch(endpoint, { headers: { Authorization: `Key ${key}` } });
      const data = await upstream.json();
      return json(data, upstream.status);
    }

    if (!models[task]) return json({ error: "Unsupported AI task." }, 400);
    if (prompt.length < 3 || prompt.length > 2000) return json({ error: "Prompt must be 3–2000 characters." }, 400);
    if ((task === "image_edit" || task === "image_to_video") && (typeof body.image_url !== "string" || !/^https:\/\//.test(body.image_url))) {
      return json({ error: "This task requires a valid HTTPS image URL." }, 400);
    }
    const payload: Record<string, unknown> = { prompt };
    if (task === "video" || task === "image_to_video") {
      const duration = String(body.duration ?? "5");
      if (duration !== "5" && duration !== "10") return json({ error: "The current Kling 2.1 Standard model supports 5-second or 10-second videos only." }, 400);
      payload.duration = duration;
      payload.aspect_ratio = "9:16";
    }
    if (task === "image_edit" || task === "image_to_video") payload.image_url = body.image_url;
    const upstream = await fetch(`https://queue.fal.run/${models[task]}`, {
      method: "POST",
      headers: { Authorization: `Key ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await upstream.json();
    return json(data, upstream.status);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "AI request failed." }, 500);
  }
});