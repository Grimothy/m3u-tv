import { useEffect, useRef } from 'react';

export function useBackHandler(handler: () => boolean) {
  const handlerRef = useRef(handler);
  handlerRef.current = handler;

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        const handled = handlerRef.current();
        if (handled) {
          e.preventDefault();
        }
      }
    };

    const onPopState = () => {
      handlerRef.current();
    };

    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('popstate', onPopState);
    return () => {
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('popstate', onPopState);
    };
  }, []);
}
