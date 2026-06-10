import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";

// AI orchestration: categorization fallback, receipt extraction, and insight
// narration. Every call uses structured outputs (output_config.format) so the
// app only ever receives schema-validated JSON — never freeform model text.
//
// The API key lives here, server-side only. The iOS app never talks to a
// model provider directly.

const client = new Anthropic(); // reads ANTHROPIC_API_KEY from env

const MODEL = "claude-opus-4-8";

const CATEGORIES = [
  "income", "housing", "utilities", "groceries", "dining", "travel",
  "transportation", "shopping", "entertainment", "health", "insurance",
  "debtPayments", "transfers", "investments", "fees", "subscriptions",
  "taxes", "miscellaneous",
] as const;

// MARK: Transaction classification (fallback after rules/provider hints)

const classificationResult = z.object({
  category: z.enum(CATEGORIES),
  subcategory: z.string().nullable(),
  isEssential: z.boolean(),
  confidence: z.number(),
});
export type ClassificationResult = z.infer<typeof classificationResult>;

export async function classifyTransaction(input: {
  merchant: string;
  rawDescription: string;
  amount: number;
}): Promise<ClassificationResult> {
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 1024,
    system:
      "You classify US personal-finance transactions into a fixed category taxonomy. " +
      "Be conservative with confidence: use < 0.5 when the descriptor is ambiguous.",
    messages: [
      {
        role: "user",
        content: `Classify this transaction.\nMerchant: ${input.merchant}\nRaw descriptor: ${input.rawDescription}\nAmount (positive = money out): ${input.amount}`,
      },
    ],
    output_config: {
      format: {
        type: "json_schema",
        schema: {
          type: "object",
          properties: {
            category: { type: "string", enum: [...CATEGORIES] },
            subcategory: { type: ["string", "null"] },
            isEssential: { type: "boolean" },
            confidence: { type: "number" },
          },
          required: ["category", "subcategory", "isEssential", "confidence"],
          additionalProperties: false,
        },
      },
    },
  });

  const text = response.content.find((b) => b.type === "text");
  return classificationResult.parse(JSON.parse(text?.type === "text" ? text.text : "{}"));
}

// MARK: Receipt extraction (fallback when on-device deterministic parse is unsure)

const receiptExtraction = z.object({
  merchant: z.string().nullable(),
  purchaseDate: z.string().nullable(), // ISO 8601 date
  subtotal: z.number().nullable(),
  tax: z.number().nullable(),
  tip: z.number().nullable(),
  total: z.number().nullable(),
  lineItems: z.array(z.object({
    name: z.string(),
    quantity: z.number(),
    price: z.number(),
  })),
  inferredCategory: z.enum(CATEGORIES).nullable(),
  extractionConfidence: z.number(),
});
export type ReceiptExtractionResult = z.infer<typeof receiptExtraction>;

export async function extractReceipt(ocrText: string): Promise<ReceiptExtractionResult> {
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 4096,
    thinking: { type: "adaptive" },
    system:
      "You extract structured data from noisy receipt OCR text. Only report values that are " +
      "actually present in the text — use null for anything you cannot find. Never invent line items.",
    messages: [
      { role: "user", content: `Extract the structured receipt data from this OCR text:\n\n${ocrText}` },
    ],
    output_config: {
      format: {
        type: "json_schema",
        schema: {
          type: "object",
          properties: {
            merchant: { type: ["string", "null"] },
            purchaseDate: { type: ["string", "null"], format: "date" },
            subtotal: { type: ["number", "null"] },
            tax: { type: ["number", "null"] },
            tip: { type: ["number", "null"] },
            total: { type: ["number", "null"] },
            lineItems: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: { type: "string" },
                  quantity: { type: "number" },
                  price: { type: "number" },
                },
                required: ["name", "quantity", "price"],
                additionalProperties: false,
              },
            },
            inferredCategory: { type: ["string", "null"], enum: [...CATEGORIES, null] },
            extractionConfidence: { type: "number" },
          },
          required: [
            "merchant", "purchaseDate", "subtotal", "tax", "tip", "total",
            "lineItems", "inferredCategory", "extractionConfidence",
          ],
          additionalProperties: false,
        },
      },
    },
  });

  const text = response.content.find((b) => b.type === "text");
  return receiptExtraction.parse(JSON.parse(text?.type === "text" ? text.text : "{}"));
}

// MARK: Insight narration (structured profile/forecast in → structured insights out)

const narratives = z.object({
  insights: z.array(z.object({
    title: z.string(),
    detail: z.string(),
    severity: z.enum(["positive", "neutral", "warning", "critical"]),
    evidence: z.array(z.string()),
    confidence: z.number(),
  })),
  recommendations: z.array(z.object({
    title: z.string(),
    detail: z.string(),
    severity: z.enum(["positive", "neutral", "warning", "critical"]),
    evidence: z.array(z.string()),
    confidence: z.number(),
  })),
});
export type Narratives = z.infer<typeof narratives>;

/**
 * Turns the deterministic SpendingProfile/SpendForecast/BudgetRiskAssessment
 * structures (computed on-device or in a backend job) into concise, evidence-
 * tied insight and recommendation copy. Input is structured data only — the
 * model never sees raw transactions, and every claim must cite the provided
 * numbers as evidence.
 */
export async function generateNarratives(structuredInputs: {
  profile: unknown;
  forecast: unknown;
  risk: unknown;
}): Promise<Narratives> {
  const itemSchema = {
    type: "object",
    properties: {
      title: { type: "string" },
      detail: { type: "string" },
      severity: { type: "string", enum: ["positive", "neutral", "warning", "critical"] },
      evidence: { type: "array", items: { type: "string" } },
      confidence: { type: "number" },
    },
    required: ["title", "detail", "severity", "evidence", "confidence"],
    additionalProperties: false,
  };

  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 4096,
    thinking: { type: "adaptive" },
    system:
      "You are the narration layer of a personal-finance copilot. You receive structured, " +
      "pre-computed financial analysis and write at most 5 insights (observations) and 3 " +
      "recommendations (concrete actions). Every claim must be backed by a number from the " +
      "input, quoted in the evidence array. Be concise and restrained. Never invent data, " +
      "never give generic advice, never moralize.",
    messages: [
      {
        role: "user",
        content: JSON.stringify(structuredInputs),
      },
    ],
    output_config: {
      format: {
        type: "json_schema",
        schema: {
          type: "object",
          properties: {
            insights: { type: "array", items: itemSchema },
            recommendations: { type: "array", items: itemSchema },
          },
          required: ["insights", "recommendations"],
          additionalProperties: false,
        },
      },
    },
  });

  const text = response.content.find((b) => b.type === "text");
  return narratives.parse(JSON.parse(text?.type === "text" ? text.text : "{}"));
}
