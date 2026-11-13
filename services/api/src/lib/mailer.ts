/**
 * Outbound email (verification, password reset, album invites).
 *
 * ADR-0011 leaves the transactional email provider as an owner decision. Until one is chosen the API
 * ships two implementations: `LogMailer` (writes the message to the structured log in development) and
 * `OutboxMailer` (keeps messages in memory so tests and local tools can read the links).
 */
export interface Mail {
  kind: 'verify_email' | 'reset_password' | 'album_invite';
  to: string;
  subject: string;
  text: string;
  /** The single action link in the message. */
  link: string;
}

export interface Mailer {
  send(mail: Mail): Promise<void>;
}

export interface MailLogger {
  info(object: Record<string, unknown>, message: string): void;
}

/** Development mailer: the link is the point, so it is logged. Never use it in production. */
export class LogMailer implements Mailer {
  readonly #logger: MailLogger;

  constructor(logger: MailLogger) {
    this.#logger = logger;
  }

  async send(mail: Mail): Promise<void> {
    this.#logger.info({ mail: { kind: mail.kind, to: mail.to, subject: mail.subject, link: mail.link } }, 'email (not delivered: log mailer)');
  }
}

/** Keeps sent messages in memory. */
export class OutboxMailer implements Mailer {
  readonly sent: Mail[] = [];

  async send(mail: Mail): Promise<void> {
    this.sent.push(mail);
  }

  last(kind?: Mail['kind']): Mail | undefined {
    const matches = kind === undefined ? this.sent : this.sent.filter((mail) => mail.kind === kind);
    return matches.at(-1);
  }
}
