import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { benchRepository } from '@/lib/supabase';
import { Spacing } from '@/theme';

interface Props {
  benchId: string;
  onClose: () => void;
}

function triState(value: boolean | null, t: (key: string) => string): string {
  if (value === null) return t('bench.unknown');
  return value ? t('bench.yes') : t('bench.no');
}

function formatDate(value: string): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(parsed);
}

export function BenchDetailCard({ benchId, onClose }: Props) {
  const { t } = useTranslation();
  const { data, isPending, isError } = useQuery({
    queryKey: ['bench', benchId],
    queryFn: () => benchRepository.findBenchById(benchId),
  });

  return (
    <ThemedView type="backgroundElement" style={styles.card} accessibilityRole="summary">
      <View style={styles.header}>
        <ThemedText type="subtitle">{t('bench.title')}</ThemedText>
        <Pressable
          onPress={onClose}
          accessibilityRole="button"
          accessibilityLabel={t('bench.close')}
          hitSlop={12}
        >
          <ThemedText themeColor="textSecondary">✕</ThemedText>
        </Pressable>
      </View>

      {isPending && <ThemedText themeColor="textSecondary">{t('bench.loading')}</ThemedText>}
      {isError && <ThemedText themeColor="textSecondary">{t('bench.error')}</ThemedText>}
      {data === null && <ThemedText themeColor="textSecondary">{t('bench.error')}</ThemedText>}

      {data ? (
        <View accessibilityLabel={t('bench.title')}>
          <ThemedText themeColor="textSecondary" type="small">
            {t(`bench.state.${data.verification_state}`)}
            {' · '}
            {t(`bench.materials.${data.material}`)}
          </ThemedText>
          <ThemedText themeColor="textSecondary" type="small">
            {t('bench.provenanceLabel')}: {t(`bench.provenance.${data.origin}`)}
            {data.source_osm_id !== null ? ` (#${data.source_osm_id})` : ''}
          </ThemedText>
          <ThemedText type="small">
            {t('bench.backrest')}: {triState(data.has_backrest, t)}
            {'   '}
            {t('bench.armrests')}: {triState(data.has_armrests, t)}
          </ThemedText>
          <ThemedText type="small">
            {t('bench.accessible')}: {triState(data.is_accessible, t)}
            {data.seats !== null ? `   ${t('bench.seats')}: ${data.seats}` : ''}
          </ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {t('bench.confirmations')}: {data.confirm_count} · {t('bench.disputes')}: {data.dispute_count}
          </ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {t('bench.lastUpdated')}: {formatDate(data.updated_at)}
          </ThemedText>
          {data.rating_count > 0 ? (
            <ThemedText type="small" themeColor="textSecondary">
              {t('bench.scenic')} {data.scenic_avg ?? '–'} · {t('bench.comfort')}{' '}
              {data.comfort_avg ?? '–'} ({data.rating_count})
            </ThemedText>
          ) : null}
        </View>
      ) : null}
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  card: {
    position: 'absolute',
    left: Spacing.three,
    right: Spacing.three,
    bottom: Spacing.four,
    borderRadius: 12,
    padding: Spacing.three,
    gap: Spacing.one,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
});
