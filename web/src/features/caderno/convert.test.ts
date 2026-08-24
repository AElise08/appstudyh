import { describe, expect, it } from "vitest";
import {
  extractQuestionText,
  extractTaskTitle,
  selectParagraphAround,
  splitParagraphToCard,
} from "./convert";

describe("splitParagraphToCard", () => {
  it("splits at the first newline", () => {
    expect(splitParagraphToCard("O que é ATP?\nA moeda energética da célula")).toEqual({
      front: "O que é ATP?",
      back: "A moeda energética da célula",
    });
  });

  it("splits at the first em dash separator", () => {
    expect(splitParagraphToCard("Mitocôndria — organela responsável pela respiração")).toEqual({
      front: "Mitocôndria",
      back: "organela responsável pela respiração",
    });
  });

  it("splits at the first colon separator", () => {
    expect(splitParagraphToCard("Fotossíntese: processo de conversão de luz em energia")).toEqual({
      front: "Fotossíntese",
      back: "processo de conversão de luz em energia",
    });
  });

  it("trims both sides", () => {
    expect(splitParagraphToCard("  Termo   —   definição  ")).toEqual({
      front: "Termo",
      back: "definição",
    });
  });

  it("prefers the newline over later separators", () => {
    expect(splitParagraphToCard("Pergunta?\nResposta — com detalhe")).toEqual({
      front: "Pergunta?",
      back: "Resposta — com detalhe",
    });
  });

  it("rejects a paragraph without separators", () => {
    expect(splitParagraphToCard("apenas um parágrafo solto")).toBeNull();
  });

  it("rejects empty sides", () => {
    expect(splitParagraphToCard("— só o verso")).toBeNull();
    expect(splitParagraphToCard("só a frente: ")).toBeNull();
    expect(splitParagraphToCard("\n\n")).toBeNull();
    expect(splitParagraphToCard("")).toBeNull();
  });
});

describe("selectParagraphAround", () => {
  it("returns the first paragraph for caret inside it", () => {
    const range = selectParagraphAround("linha um\nlinha dois", 4);
    expect(range).toEqual({ text: "linha um", start: 0, end: 8 });
  });

  it("returns the last paragraph without trailing newline", () => {
    const range = selectParagraphAround("aaa\nbbb", 5);
    expect(range).toEqual({ text: "bbb", start: 4, end: 7 });
  });

  it("clamps out-of-range carets", () => {
    expect(selectParagraphAround("abc", 99)?.text).toBe("abc");
    expect(selectParagraphAround("abc", -3)?.start).toBe(0);
  });

  it("returns null for blank paragraphs", () => {
    expect(selectParagraphAround("", 0)).toBeNull();
    expect(selectParagraphAround("ok\n   \nfim", 5)).toBeNull();
  });
});

describe("extractTaskTitle", () => {
  it("collapses whitespace into a single-line title", () => {
    expect(extractTaskTitle("  Ler   capítulo\ntrês  ")).toBe("Ler capítulo três");
  });

  it("rejects blank titles", () => {
    expect(extractTaskTitle("   ")).toBeNull();
  });
});

describe("extractQuestionText", () => {
  it("trims and keeps interior newlines", () => {
    expect(extractQuestionText("  Explique:\na lei de Ohm ")).toBe("Explique:\na lei de Ohm");
  });

  it("rejects blank bodies", () => {
    expect(extractQuestionText(" \n ")).toBeNull();
  });
});
