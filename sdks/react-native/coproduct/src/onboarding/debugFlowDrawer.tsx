import { useRef, useState } from 'react';
import {
  ActivityIndicator,
  Animated,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';

export interface DebugFlowDrawerProps {
  onRestartFlow: () => Promise<void>;
  onRefresh: () => Promise<void>;
}

const CLOSED_WIDTH = 28;
const OPEN_WIDTH = 168;

// A small tab docked to the right edge of the screen that slides out a
// two-button panel ("Restart flow", "Refresh"), so a developer iterating on
// a flow's content through the Coproduct platform MCP tools can see the
// change on a running device without a full app kill/relaunch. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/debug_flow_drawer.dart.
// __DEV__ gating happens at the call site in CoproductOnboardingFlow, not
// inside this component.
export function DebugFlowDrawer({
  onRestartFlow,
  onRefresh,
}: DebugFlowDrawerProps) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const width = useRef(new Animated.Value(CLOSED_WIDTH)).current;

  const toggle = (next: boolean) => {
    setOpen(next);
    Animated.timing(width, {
      toValue: next ? OPEN_WIDTH : CLOSED_WIDTH,
      duration: 200,
      useNativeDriver: false,
    }).start();
  };

  const run = async (action: () => Promise<void>) => {
    if (busy) return;
    setBusy(true);
    try {
      await action();
    } finally {
      setBusy(false);
      toggle(false);
    }
  };

  return (
    <View style={styles.container} pointerEvents="box-none">
      <Animated.View style={[styles.panel, { width }]}>
        {open ? (
          <View style={styles.openPanel}>
            <View style={styles.header}>
              <Text style={styles.headerText}>DEBUG</Text>
              <Pressable onPress={() => toggle(false)} hitSlop={8}>
                <Text style={styles.chevron}>{'›'}</Text>
              </Pressable>
            </View>
            <ActionButton
              label="Restart flow"
              busy={busy}
              onPress={() => run(onRestartFlow)}
            />
            <ActionButton
              label="Refresh"
              busy={busy}
              onPress={() => run(onRefresh)}
            />
          </View>
        ) : (
          <Pressable style={styles.closedTab} onPress={() => toggle(true)}>
            <Text style={styles.chevron}>{'‹'}</Text>
          </Pressable>
        )}
      </Animated.View>
    </View>
  );
}

function ActionButton({
  label,
  busy,
  onPress,
}: {
  label: string;
  busy: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      style={styles.actionButton}
      onPress={busy ? undefined : onPress}
      disabled={busy}
    >
      {busy ? <ActivityIndicator size="small" color="#ffffffb3" /> : null}
      <Text style={styles.actionLabel}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: 0,
    alignItems: 'flex-end',
    justifyContent: 'center',
  },
  panel: {
    backgroundColor: '#222222e6',
    borderTopLeftRadius: 10,
    borderBottomLeftRadius: 10,
    overflow: 'hidden',
  },
  closedTab: {
    width: 28,
    height: 56,
    alignItems: 'center',
    justifyContent: 'center',
  },
  chevron: { color: '#ffffff', fontSize: 18 },
  openPanel: { paddingVertical: 10, paddingHorizontal: 8 },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: 8 },
  headerText: { flex: 1, color: '#ffffffb3', fontSize: 11, fontWeight: 'bold' },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    paddingHorizontal: 6,
    backgroundColor: '#ffffff14',
    borderRadius: 6,
    marginBottom: 6,
  },
  actionLabel: { color: '#ffffff', fontSize: 12, marginLeft: 6 },
});
