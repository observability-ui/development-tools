// MIT LICENSE: https://github.com/shikijs/shiki/blob/main/packages/cli/src/cli.ts

import type { BundledLanguage } from "shiki";
import { parse } from "node:path";
import process from "node:process";
import cac from "cac";
import { version } from "./package.json";
import { codeToANSI } from "./code-to-ansi";

async function readStdin() {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

export async function run(
  argv = process.argv,
  log = console.log,
): Promise<void> {
  const cli = cac("shiki");

  cli
    .option("--theme <theme>", "Color theme to use", {
      default: "vitesse-dark",
    })
    .option("--lang <lang>", "Programming language")
    .option("--color", "Force color output")
    .help()
    .version(version);

  const { options, args } = cli.parse(argv);
  const files = args;
  const theme = options.theme;
  let lang = options.lang as BundledLanguage | undefined;

  // No files, and terminal is interactive
  if (files.length === 0 && process.stdin.isTTY) {
    cli.outputHelp();
    return;
  }

  if (files.length > 0) {
    const codes = await Promise.all(
      files.map(async (path) => {
        const fileLang = lang || parse(path).ext.slice(1);
        if (!fileLang) {
          console.error(
            `Error: Failed to resolve language for "${path}". Please specify with --lang.`,
          );
          process.exit(1);
        }
        const type = Bun.file(path);
        const content = await Bun.file(path).text();
        return await codeToANSI(content, fileLang as BundledLanguage, theme);
      }),
    );
    for (const code of codes) log(code);
  } else {
    // Input from pipe
    if (!lang) {
      lang = "text" as BundledLanguage;
    }
    const content = await readStdin();
    const code = await codeToANSI(content, lang, theme);
    log(code);
  }
}

run();
