import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, StyleSheet, ActivityIndicator, ScrollView, FlatList, Image } from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { useViewer } from '../context/ViewerContext';
import { useMenu } from '../context/MenuContext';
import { favoritesService } from '../services/FavoritesService';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { LiveTVCard } from '../components/LiveTVCard';
import { MovieCard } from '../components/MovieCard';
import { SeriesCard } from '../components/SeriesCard';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamVodStream, XtreamSeries, WatchProgress } from '../types/xtream';

export function HomeScreen({ navigation }: DrawerScreenPropsType<'Home'>) {
  const { isConfigured, isLoading, isM3UEditor, loadSavedCredentials, fetchLiveStreams, fetchVodStreams, fetchSeries, vodCategories } = useXtream();
  const { activeViewer, getRecentlyWatched } = useViewer();
  const { isSidebarActive, setSidebarActive } = useMenu();
  const [liveStreams, setLiveStreams] = useState<XtreamLiveStream[]>([]);
  const [vodStreams, setVodStreams] = useState<XtreamVodStream[]>([]);
  const [seriesList, setSeriesList] = useState<XtreamSeries[]>([]);
  const [contentLoading, setContentLoading] = useState(false);
  const [recentlyWatched, setRecentlyWatched] = useState<WatchProgress[]>([]);
  const [favoriteStreams, setFavoriteStreams] = useState<XtreamLiveStream[]>([]);

  useEffect(() => {
    loadSavedCredentials();
  }, [loadSavedCredentials]);

  useEffect(() => {
    if (isConfigured) {
      loadContent();
    }
  }, [isConfigured]);

  useEffect(() => {
    if (isM3UEditor && activeViewer) {
      getRecentlyWatched(undefined, 10).then(setRecentlyWatched);
    }
  }, [isM3UEditor, activeViewer, getRecentlyWatched]);

  const loadContent = async () => {
    setContentLoading(true);
    const [live, vod, series] = await Promise.all([fetchLiveStreams(), fetchVodStreams(), fetchSeries()]);
    setLiveStreams(live);
    let finalVod = vod;
    if (finalVod.length === 0 && vodCategories.length > 0) {
      const all = await Promise.all(vodCategories.map((c) => fetchVodStreams(c.category_id)));
      const seen = new Set<number>();
      finalVod = all.flat().filter((s) => {
        if (seen.has(s.stream_id)) return false;
        seen.add(s.stream_id);
        return true;
      });
    }
    setVodStreams(finalVod);
    setSeriesList(series);
    await favoritesService.load();
    const favIds = new Set(favoritesService.getAll());
    setFavoriteStreams(live.filter((s) => favIds.has(s.stream_id)));
    setContentLoading(false);
  };

  const handleContinueWatching = useCallback((item: WatchProgress) => {
    if (item.content_type === 'vod') {
      const vod = vodStreams.find((v) => v.stream_id === item.stream_id);
      if (vod) navigation.navigate('Details', { item: vod });
    } else if (item.content_type === 'episode' && item.series_id) {
      const series = seriesList.find((s) => s.series_id === item.series_id);
      if (series) navigation.navigate('SeriesDetails', { item: series });
    }
  }, [vodStreams, seriesList, navigation]);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Connecting...</Text>
      </View>
    );
  }

  if (!isConfigured) {
    return (
      <View style={styles.welcomeContainer}>
        <Text style={styles.title}>Welcome to M3U TV</Text>
        <Text style={styles.subtitle}>Connect to your Xtream service to get started</Text>
        <FocusablePressable
          preferredFocus
          style={({ isFocused }) => [styles.settingsButton, isFocused && styles.buttonFocused]}
          onSelect={() => navigation.navigate('Settings')}
        >
          {({ isFocused }) => <Text style={[styles.settingsButtonText, isFocused && styles.buttonTextFocused]}>Go to Settings</Text>}
        </FocusablePressable>
      </View>
    );
  }

  if (contentLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Loading content...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent}>
      {/* Continue Watching Row */}
      {recentlyWatched.filter((w) => w.content_type !== 'live').length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>Continue Watching</Text>
          <View style={styles.continueWatchingList}>
            <FlatList
              data={recentlyWatched.filter((w) => w.content_type !== 'live')}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              style={styles.rowList}
              showsHorizontalScrollIndicator={false}
              keyExtractor={(item) => `${item.content_type}-${item.stream_id}`}
              renderItem={({ item: prog, index }) => {
                const vod = prog.content_type === 'vod'
                  ? vodStreams.find((v) => v.stream_id === prog.stream_id)
                  : undefined;
                const series = prog.content_type === 'episode' && prog.series_id
                  ? seriesList.find((s) => s.series_id === prog.series_id)
                  : undefined;
                const cover = vod?.stream_icon || series?.cover || '';
                const title = vod?.name || series?.name || `Stream ${prog.stream_id}`;
                const pct = prog.duration_seconds && prog.duration_seconds > 0
                  ? Math.min(prog.position_seconds / prog.duration_seconds, 1)
                  : 0;
                if (!vod && !series) return null;
                return (
                  <FocusablePressable
                    onSelect={() => handleContinueWatching(prog)}
                    onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
                    style={({ isFocused }) => [styles.continueCard, isFocused && styles.continueCardFocused]}
                  >
                    {() => (
                      <View style={styles.continueCardInner}>
                        <Image source={{ uri: cover }} style={styles.continueCover} resizeMode="cover" />
                        {pct > 0 && (
                          <View style={styles.continueProgressBg}>
                            <View style={[styles.continueProgressFill, { width: `${Math.round(pct * 100)}%` as any }]} />
                          </View>
                        )}
                        <Text style={styles.continueTitle} numberOfLines={2}>{title}</Text>
                      </View>
                    )}
                  </FocusablePressable>
                );
              }}
            />
          </View>
        </View>
      )}

      {/* Favorites Row */}
      {favoriteStreams.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>★ Favorites</Text>
          <View style={styles.liveTvRowList}>
            <FlatList
              data={favoriteStreams}
              renderItem={({ item, index }: { item: XtreamLiveStream; index: number }) => (
                <LiveTVCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              keyExtractor={(item) => String(item.stream_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}

      {/* Live TV Row */}
      {liveStreams.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>Live TV</Text>
          <View style={styles.liveTvRowList}>
            <FlatList
              data={liveStreams}
              renderItem={({ item, index }: { item: XtreamLiveStream; index: number }) => (
                <LiveTVCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              keyExtractor={(item) => String(item.stream_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}

      {/* Movies Row */}
      {vodStreams.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>Movies</Text>
          <View style={styles.posterRowList}>
            <FlatList
              data={vodStreams}
              renderItem={({ item, index }: { item: XtreamVodStream; index: number }) => (
                <MovieCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              keyExtractor={(item) => String(item.stream_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}

      {/* Series Row */}
      {seriesList.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>Series</Text>
          <View style={styles.posterRowList}>
            <FlatList
              data={seriesList}
              renderItem={({ item, index }: { item: XtreamSeries; index: number }) => (
                <SeriesCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              keyExtractor={(item) => String(item.series_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scrollView: {
    overflow: 'visible',
  },
  scrollContent: {
    paddingVertical: scaledPixels(40),
    overflow: 'visible',
  },
  welcomeContainer: {
    flex: 1,
    backgroundColor: colors.background,
    padding: scaledPixels(40),
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
    marginTop: scaledPixels(20),
  },
  title: {
    fontSize: scaledPixels(48),
    fontWeight: 'bold',
    color: colors.text,
    textAlign: 'center',
    marginBottom: scaledPixels(8),
  },
  subtitle: {
    fontSize: scaledPixels(24),
    color: colors.textSecondary,
    textAlign: 'center',
    marginBottom: scaledPixels(60),
  },
  settingsButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: scaledPixels(40),
    paddingVertical: scaledPixels(20),
    borderRadius: scaledPixels(12),
    borderWidth: 3,
    borderColor: 'transparent',
  },
  settingsButtonText: {
    color: colors.textOnPrimary,
    fontSize: scaledPixels(24),
    fontWeight: '600',
  },
  buttonFocused: {
    transform: [{ scale: 1.08 }],
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  buttonTextFocused: {
    color: colors.textOnPrimary,
  },
  rowContainer: {
    marginBottom: scaledPixels(30),
    paddingHorizontal: scaledPixels(20),
    overflow: 'visible',
  },
  rowTitle: {
    color: colors.text,
    fontSize: scaledPixels(32),
    fontWeight: 'bold',
    marginBottom: scaledPixels(15),
    marginLeft: scaledPixels(10),
  },
  liveTvRowList: {
    height: scaledPixels(224),
    overflow: 'visible',
  },
  posterRowList: {
    height: scaledPixels(390),
    overflow: 'visible',
  },
  rowList: {
    overflow: 'visible',
  },
  continueWatchingList: {
    height: scaledPixels(230),
    overflow: 'visible',
  },
  continueCard: {
    width: scaledPixels(180),
    marginHorizontal: scaledPixels(12),
    borderRadius: scaledPixels(8),
    borderWidth: 3,
    borderColor: 'transparent',
  },
  continueCardInner: {
    borderRadius: scaledPixels(6),
    overflow: 'hidden',
  },
  continueCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  continueCover: {
    width: '100%',
    height: scaledPixels(160),
    borderRadius: scaledPixels(8),
  },
  continueProgressBg: {
    height: scaledPixels(4),
    backgroundColor: 'rgba(255,255,255,0.2)',
    marginTop: scaledPixels(4),
    borderRadius: scaledPixels(2),
    overflow: 'hidden',
  },
  continueProgressFill: {
    height: '100%',
    backgroundColor: colors.primary,
  },
  continueTitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(16),
    marginTop: scaledPixels(6),
    paddingHorizontal: scaledPixels(4),
  },
});
