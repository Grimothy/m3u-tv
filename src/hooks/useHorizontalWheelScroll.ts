import { useEffect, useRef } from 'react';
import { Platform, View } from 'react-native';

/**
 * On web, converts vertical mouse wheel events to horizontal scrolling
 * for the best scrollable child element inside the ref'd container.
 * Uses a MutationObserver to re-detect when content changes (e.g. categories load async).
 * Marks the scrollable element with `.m3u-scroll` for styled scrollbar CSS.
 * Returns a ref to attach to the container View wrapping a horizontal ScrollView.
 * No-op on native platforms.
 */
export function useHorizontalWheelScroll() {
  const ref = useRef<View>(null);

  useEffect(() => {
    if (Platform.OS !== 'web') return;
    const el = ref.current as unknown as HTMLElement;
    if (!el?.addEventListener) return;

    let scrollableEl: HTMLElement | null = null;

    /**
     * Scan all child divs to find the one with the largest horizontal overflow.
     * Requires >100px overflow to avoid matching truncated text buttons.
     */
    const findScrollable = (): HTMLElement | null => {
      const divs = el.querySelectorAll('div');
      let bestDiv: HTMLElement | null = null;
      let bestOverflow = 0;
      for (const div of Array.from(divs)) {
        const orig = div.style.overflowX;
        div.style.overflowX = 'auto';
        const overflow = div.scrollWidth - div.clientWidth;
        div.style.overflowX = orig;
        if (overflow > 100 && overflow > bestOverflow) {
          bestOverflow = overflow;
          bestDiv = div;
        }
      }
      return bestDiv;
    };

    const applyScrollStyles = (): void => {
      const found = findScrollable();
      if (found && found !== scrollableEl) {
        // Clean up old element
        if (scrollableEl) {
          scrollableEl.classList.remove('m3u-scroll');
          scrollableEl.style.overflowX = '';
        }
        scrollableEl = found;
        found.style.overflowX = 'auto';
        found.classList.add('m3u-scroll');
      }
    };

    const handler = (e: WheelEvent) => {
      if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
      if (!scrollableEl) applyScrollStyles();
      if (scrollableEl) {
        e.preventDefault();
        scrollableEl.scrollLeft += e.deltaY;
      }
    };

    // Initial attempt
    applyScrollStyles();

    // Watch for DOM changes (e.g. categories loading async) and re-detect
    const observer = new MutationObserver(() => {
      applyScrollStyles();
    });
    observer.observe(el, { childList: true, subtree: true });

    el.addEventListener('wheel', handler, { passive: false });
    return () => {
      observer.disconnect();
      el.removeEventListener('wheel', handler);
      if (scrollableEl) {
        scrollableEl.classList.remove('m3u-scroll');
      }
      scrollableEl = null;
    };
  }, []);

  return ref;
}
