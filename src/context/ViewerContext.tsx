import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import { getSecureItem, setSecureItem } from '../services/secureStorage';
import { xtreamService } from '../services/XtreamService';
import { PlaylistViewer, WatchProgress, UpdateProgressParams, WatchContentType } from '../types/xtream';
import { useXtream } from './XtreamContext';

const VIEWER_STORAGE_KEY = 'm3ue_tv_active_viewer';

interface ViewerState {
  activeViewer: PlaylistViewer | null;
  viewers: PlaylistViewer[];
  isLoading: boolean;
}

interface ViewerContextValue extends ViewerState {
  loadViewers: () => Promise<void>;
  setActiveViewer: (viewer: PlaylistViewer) => Promise<void>;
  createViewer: (name: string) => Promise<PlaylistViewer | null>;
  getProgress: (contentType: WatchContentType, streamId: number) => Promise<WatchProgress | null>;
  updateProgress: (params: Omit<UpdateProgressParams, 'viewer_id'>) => Promise<void>;
  getSeriesProgress: (seriesId: number) => Promise<WatchProgress[]>;
  getRecentlyWatched: (type?: WatchContentType, limit?: number) => Promise<WatchProgress[]>;
}

const ViewerContext = createContext<ViewerContextValue | null>(null);

export function ViewerProvider({ children }: { children: ReactNode }) {
  const { isConfigured, isM3UEditor } = useXtream();

  const [state, setState] = useState<ViewerState>({
    activeViewer: null,
    viewers: [],
    isLoading: false,
  });

  const loadViewers = useCallback(async () => {
    if (!isConfigured || !isM3UEditor) return;

    setState((prev) => ({ ...prev, isLoading: true }));
    try {
      const viewers = await xtreamService.getViewers();
      const savedUlid = await getSecureItem(VIEWER_STORAGE_KEY);

      let activeViewer: PlaylistViewer | null = null;
      if (savedUlid) {
        activeViewer = viewers.find((v) => v.ulid === savedUlid) ?? null;
      }
      // Default to Admin viewer (first is_admin=true, which is ordered first by backend)
      if (!activeViewer) {
        activeViewer = viewers.find((v) => v.is_admin) ?? viewers[0] ?? null;
        if (activeViewer) {
          await setSecureItem(VIEWER_STORAGE_KEY, activeViewer.ulid);
        }
      }

      setState({ viewers, activeViewer, isLoading: false });
    } catch (error) {
      console.error('Failed to load viewers:', error);
      setState((prev) => ({ ...prev, isLoading: false }));
    }
  }, [isConfigured, isM3UEditor]);

  // Load viewers when connected to m3u-editor backend
  useEffect(() => {
    if (isConfigured && isM3UEditor) {
      loadViewers();
    } else if (!isConfigured) {
      setState({ activeViewer: null, viewers: [], isLoading: false });
    }
  }, [isConfigured, isM3UEditor, loadViewers]);

  const setActiveViewer = useCallback(async (viewer: PlaylistViewer) => {
    await setSecureItem(VIEWER_STORAGE_KEY, viewer.ulid);
    setState((prev) => ({ ...prev, activeViewer: viewer }));
  }, []);

  const createViewer = useCallback(
    async (name: string): Promise<PlaylistViewer | null> => {
      try {
        const viewer = await xtreamService.createViewer(name);
        setState((prev) => ({ ...prev, viewers: [...prev.viewers, viewer] }));
        return viewer;
      } catch (error) {
        console.error('Failed to create viewer:', error);
        return null;
      }
    },
    []
  );

  const getProgress = useCallback(
    async (contentType: WatchContentType, streamId: number): Promise<WatchProgress | null> => {
      if (!state.activeViewer) return null;
      try {
        return await xtreamService.getProgress(state.activeViewer.ulid, contentType, streamId);
      } catch {
        return null;
      }
    },
    [state.activeViewer]
  );

  const updateProgress = useCallback(
    async (params: Omit<UpdateProgressParams, 'viewer_id'>): Promise<void> => {
      if (!state.activeViewer) return;
      try {
        await xtreamService.updateProgress({ ...params, viewer_id: state.activeViewer.ulid });
      } catch (error) {
        console.error('Failed to update progress:', error);
      }
    },
    [state.activeViewer]
  );

  const getSeriesProgress = useCallback(
    async (seriesId: number): Promise<WatchProgress[]> => {
      if (!state.activeViewer) return [];
      try {
        return await xtreamService.getSeriesProgress(state.activeViewer.ulid, seriesId);
      } catch {
        return [];
      }
    },
    [state.activeViewer]
  );

  const getRecentlyWatched = useCallback(
    async (type?: WatchContentType, limit: number = 20): Promise<WatchProgress[]> => {
      if (!state.activeViewer) return [];
      try {
        return await xtreamService.getRecentlyWatched(state.activeViewer.ulid, type, limit);
      } catch {
        return [];
      }
    },
    [state.activeViewer]
  );

  const value: ViewerContextValue = {
    ...state,
    loadViewers,
    setActiveViewer,
    createViewer,
    getProgress,
    updateProgress,
    getSeriesProgress,
    getRecentlyWatched,
  };

  return <ViewerContext.Provider value={value}>{children}</ViewerContext.Provider>;
}

export function useViewer(): ViewerContextValue {
  const context = useContext(ViewerContext);
  if (!context) {
    throw new Error('useViewer must be used within a ViewerProvider');
  }
  return context;
}
