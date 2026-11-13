import { useMutation, useQueryClient } from '@tanstack/react-query';
import { type SyntheticEvent, useState } from 'react';
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router';
import { api, ApiError } from '../api/client.ts';
import { meQueryKey } from '../auth/RequireAuth.tsx';
import { usePageTitle } from '../app/use-page-title.ts';
import { ErrorNotice, Field } from '../components/parts.tsx';

function friendly(error: unknown): unknown {
  if (
    error instanceof ApiError &&
    error.status === 403 &&
    error.code.includes('EMAIL_NOT_VERIFIED')
  ) {
    return new Error('Check your inbox: you need to confirm your email address before signing in.');
  }
  if (error instanceof ApiError && error.status === 401) {
    return new Error('That email and password do not match.');
  }
  return error;
}

export function SignInPage() {
  usePageTitle('Sign in');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const navigate = useNavigate();
  const location = useLocation();
  const client = useQueryClient();
  const from = (location.state as { from?: string } | null)?.from ?? '/';
  const signIn = useMutation({
    mutationFn: () => api.signIn({ email, password }),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: meQueryKey });
      void navigate(from, { replace: true });
    },
  });
  const submit = (event: SyntheticEvent) => {
    event.preventDefault();
    signIn.mutate();
  };
  return (
    <form className="card narrow" onSubmit={submit} aria-labelledby="signin-title">
      <h1 id="signin-title">Sign in</h1>
      <Field
        id="email"
        label="Email"
        type="email"
        autoComplete="email"
        value={email}
        onChange={setEmail}
        required
      />
      <Field
        id="password"
        label="Password"
        type="password"
        autoComplete="current-password"
        value={password}
        onChange={setPassword}
        required
      />
      <ErrorNotice error={signIn.error === null ? null : friendly(signIn.error)} />
      <button type="submit" disabled={signIn.isPending}>
        {signIn.isPending ? 'Signing in…' : 'Sign in'}
      </button>
      <p>
        <Link to="/forgot-password">Forgot your password?</Link>
      </p>
      <p>
        New here? <Link to="/sign-up">Create an account</Link>
      </p>
    </form>
  );
}

export function SignUpPage() {
  usePageTitle('Create account');
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const signUp = useMutation({ mutationFn: () => api.signUp({ name, email, password }) });
  if (signUp.isSuccess) {
    return (
      <section className="card narrow" role="status">
        <h1>Check your email</h1>
        <p>
          We sent a confirmation link to <strong>{email}</strong>. Open it, then{' '}
          <Link to="/sign-in">sign in</Link>.
        </p>
      </section>
    );
  }
  return (
    <form
      className="card narrow"
      aria-labelledby="signup-title"
      onSubmit={(event) => {
        event.preventDefault();
        signUp.mutate();
      }}
    >
      <h1 id="signup-title">Create your account</h1>
      <p className="muted">
        The camera and your local library work without an account. An account adds cloud backup and
        this dashboard.
      </p>
      <Field id="name" label="Name" autoComplete="name" value={name} onChange={setName} required />
      <Field
        id="email"
        label="Email"
        type="email"
        autoComplete="email"
        value={email}
        onChange={setEmail}
        required
      />
      <Field
        id="password"
        label="Password"
        type="password"
        autoComplete="new-password"
        value={password}
        onChange={setPassword}
        hint="At least 10 characters."
        minLength={10}
        required
      />
      <ErrorNotice error={signUp.error} />
      <button type="submit" disabled={signUp.isPending}>
        {signUp.isPending ? 'Creating…' : 'Create account'}
      </button>
      <p>
        Already have an account? <Link to="/sign-in">Sign in</Link>
      </p>
    </form>
  );
}

export function ForgotPasswordPage() {
  usePageTitle('Reset password');
  const [email, setEmail] = useState('');
  const reset = useMutation({
    mutationFn: () => api.requestPasswordReset(email, `${window.location.origin}/reset-password`),
  });
  if (reset.isSuccess) {
    return (
      <section className="card narrow" role="status">
        <h1>Check your email</h1>
        <p>If an account exists for {email}, we sent a link to choose a new password.</p>
        <p>
          <Link to="/sign-in">Back to sign in</Link>
        </p>
      </section>
    );
  }
  return (
    <form
      className="card narrow"
      aria-labelledby="forgot-title"
      onSubmit={(event) => {
        event.preventDefault();
        reset.mutate();
      }}
    >
      <h1 id="forgot-title">Reset your password</h1>
      <Field
        id="email"
        label="Email"
        type="email"
        autoComplete="email"
        value={email}
        onChange={setEmail}
        required
      />
      <ErrorNotice error={reset.error} />
      <button type="submit" disabled={reset.isPending}>
        Send reset link
      </button>
    </form>
  );
}

export function ResetPasswordPage() {
  usePageTitle('Choose a new password');
  const [params] = useSearchParams();
  const token = params.get('token') ?? '';
  const [password, setPassword] = useState('');
  const reset = useMutation({ mutationFn: () => api.resetPassword(token, password) });
  if (token === '') {
    return (
      <section className="card narrow" role="alert">
        <h1>This link is not valid</h1>
        <p>
          Ask for a new one on the <Link to="/forgot-password">reset page</Link>.
        </p>
      </section>
    );
  }
  if (reset.isSuccess) {
    return (
      <section className="card narrow" role="status">
        <h1>Password updated</h1>
        <p>
          <Link to="/sign-in">Sign in with your new password</Link>
        </p>
      </section>
    );
  }
  return (
    <form
      className="card narrow"
      aria-labelledby="reset-title"
      onSubmit={(event) => {
        event.preventDefault();
        reset.mutate();
      }}
    >
      <h1 id="reset-title">Choose a new password</h1>
      <Field
        id="password"
        label="New password"
        type="password"
        autoComplete="new-password"
        value={password}
        onChange={setPassword}
        hint="At least 10 characters."
        minLength={10}
        required
      />
      <ErrorNotice error={reset.error} />
      <button type="submit" disabled={reset.isPending}>
        Update password
      </button>
    </form>
  );
}
