export type CheckName = 'links' | 'requirements' | 'adrs' | 'tasks' | 'index' | 'traceability';

export interface DocError {
  check: CheckName;
  file: string;
  /** 1-based line number, or null when the error concerns the whole file. */
  line: number | null;
  message: string;
}

export function docError(check: CheckName, file: string, line: number | null, message: string): DocError {
  return { check, file, line, message };
}

export function formatError(error: DocError): string {
  const location = error.line === null ? error.file : `${error.file}:${error.line}`;
  return `${location} [${error.check}] ${error.message}`;
}

export function compareErrors(a: DocError, b: DocError): number {
  return (
    a.file.localeCompare(b.file) ||
    (a.line ?? 0) - (b.line ?? 0) ||
    a.check.localeCompare(b.check) ||
    a.message.localeCompare(b.message)
  );
}
