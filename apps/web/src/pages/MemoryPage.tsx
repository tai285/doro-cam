import { Link, useParams } from 'react-router';
import { usePageTitle } from '../app/use-page-title.ts';

/** Placeholder. Memory detail with motion playback arrives with P7. */
export function MemoryPage() {
  const { id } = useParams();
  usePageTitle('Memory');
  return (
    <>
      <h1>Memory</h1>
      <p>
        Memory <code>{id}</code>
      </p>
      <p>
        <Link to="/">Back to library</Link>
      </p>
    </>
  );
}
