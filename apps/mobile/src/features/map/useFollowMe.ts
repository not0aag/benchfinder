import * as Location from 'expo-location';
import { useCallback, useState } from 'react';

export function useFollowMe() {
  const [following, setFollowing] = useState(false);
  const [denied, setDenied] = useState(false);

  const toggle = useCallback(async () => {
    if (following) {
      setFollowing(false);
      return;
    }
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') {
      setDenied(true);
      return;
    }
    setDenied(false);
    setFollowing(true);
  }, [following]);

  return { following, denied, toggle };
}
