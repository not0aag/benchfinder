import Ionicons from '@expo/vector-icons/Ionicons';
import {
  Camera,
  Layer,
  Map,
  RasterSource,
  UserLocation,
  VectorSource,
} from '@maplibre/maplibre-react-native';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { tilesUrl } from '@/lib/supabase';
import { Spacing } from '@/theme';
import { useTheme } from '@/theme/use-theme';

import { BenchDetailCard } from './BenchDetailCard';
import { useFollowMe } from './useFollowMe';

const EMPTY_STYLE = { version: 8 as const, sources: {}, layers: [] };

const OAKVILLE: [number, number] = [-79.68, 43.43];

export default function MapScreen() {
  const { t } = useTranslation();
  const theme = useTheme();
  const { following, denied, toggle } = useFollowMe();
  const [selectedBenchId, setSelectedBenchId] = useState<string | null>(null);

  return (
    <View style={styles.container}>
      <Map
        style={styles.map}
        mapStyle={EMPTY_STYLE}
        attribution={false}
        logo={false}
        onPress={() => setSelectedBenchId(null)}
      >
        <Camera
          initialViewState={{ center: OAKVILLE, zoom: 12 }}
          {...(following ? { trackUserLocation: 'default' as const } : {})}
        />

        {/* TODO(protomaps): dev-only raster basemap, swap for PMTiles on R2 */}
        <RasterSource
          id="basemap"
          tiles={['https://tile.openstreetmap.org/{z}/{x}/{y}.png']}
          tileSize={256}
          attribution="© OpenStreetMap contributors"
        >
          <Layer type="raster" id="basemap-tiles" />
        </RasterSource>

        <VectorSource
          id="benches"
          tiles={[`${tilesUrl}/benches/{z}/{x}/{y}.mvt?v=1`]}
          maxzoom={14}
          onPress={(event) => {
            const id = event.nativeEvent.features[0]?.properties?.['id'];
            if (typeof id === 'string') {
              setSelectedBenchId(id);
            }
          }}
        >
          <Layer
            type="circle"
            id="bench-circles"
            source-layer="benches"
            paint={{
              'circle-radius': 5,
              'circle-stroke-width': 1.5,
              'circle-stroke-color': '#ffffff',
              // marker colours per BENCHFINDER_ARCHITECTURE.md section 5
              'circle-color': [
                'match',
                ['get', 'verification_state'],
                'unconfirmed',
                '#f59e0b',
                'community',
                '#3b82f6',
                'confirmed',
                '#22c55e',
                'verified',
                '#15803d',
                'disputed',
                '#ef4444',
                '#9ca3af',
              ],
            }}
          />
        </VectorSource>

        {following ? <UserLocation /> : null}
      </Map>

      <Pressable
        onPress={toggle}
        accessibilityRole="button"
        accessibilityLabel={following ? t('map.stopFollowing') : t('map.followMe')}
        style={[styles.followButton, { backgroundColor: theme.backgroundElement }]}
      >
        <Ionicons
          name={following ? 'locate' : 'locate-outline'}
          size={22}
          color={following ? '#3b82f6' : theme.text}
        />
      </Pressable>

      {denied ? (
        <View style={[styles.toast, { backgroundColor: theme.backgroundElement }]}>
          <ThemedText type="small" themeColor="textSecondary">
            {t('map.locationDenied')}
          </ThemedText>
        </View>
      ) : null}

      <View style={styles.attribution} accessibilityRole="text">
        <ThemedText type="small" themeColor="textSecondary">
          {t('map.attribution')}
        </ThemedText>
      </View>

      {selectedBenchId ? (
        <BenchDetailCard benchId={selectedBenchId} onClose={() => setSelectedBenchId(null)} />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  map: { flex: 1 },
  followButton: {
    position: 'absolute',
    top: Spacing.four,
    right: Spacing.three,
    borderRadius: 24,
    padding: Spacing.two,
    elevation: 3,
  },
  toast: {
    position: 'absolute',
    top: Spacing.six,
    alignSelf: 'center',
    borderRadius: 8,
    paddingHorizontal: Spacing.three,
    paddingVertical: Spacing.one,
  },
  attribution: {
    position: 'absolute',
    bottom: Spacing.one,
    right: Spacing.two,
  },
});
