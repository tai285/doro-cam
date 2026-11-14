import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/domain/camera/capabilities.dart';
import 'package:doro_cam/domain/camera/capture_intent.dart';
import 'package:doro_cam/domain/camera/control_availability.dart';
import 'package:doro_cam/domain/experience/experience.dart';
import 'package:doro_cam/domain/experience/scenario.dart';
import 'package:doro_cam/features/camera/application/camera_controller.dart';
import 'package:doro_cam/features/camera/application/stops.dart';
import 'package:doro_cam/features/presets/preset_mapping.dart';
import 'package:doro_camera/doro_camera.dart' as cam;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The control strip, scenario / preset / look chips and the Experience switcher (docs/design/camera-ux.md).
/// A control that the camera does not support is not in the strip at all; "Why can't I…?" explains each absence (CAM-005).
class ControlPanel extends ConsumerStatefulWidget {
  const ControlPanel({super.key});

  @override
  ConsumerState<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends ConsumerState<ControlPanel> {
  bool? _manualOverride;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cameraControllerProvider);
    final controller = ref.read(cameraControllerProvider.notifier);
    final availability = controlAvailability(state.caps);
    final settings = state.settings;
    final showManual =
        _manualOverride ?? state.experience.workflow.manualDialsVisible;
    bool shown(Control c, IntentField f) =>
        (availability[c]?.isVisible ?? false) && !state.disabled.contains(f);
    final backLenses = state.cameras
        .where(
          (c) =>
              c.facing == cam.CameraFacing.back &&
              c.source == state.camera?.source,
        )
        .toList();

    final chips = <Widget>[
      if (shown(Control.zoom, IntentField.zoom))
        _ControlChip(
          key: const Key('control-zoom'),
          label: 'Zoom',
          value:
              formatZoom(settings?.zoom ?? 1) +
              ((settings?.digitalZoom ?? false) ? ' digital' : ''),
          onTap: () => _sheet(const _ZoomSheet()),
          adjusted: state.result?.adjustmentFor(IntentField.zoom) != null,
        ),
      if (showManual && shown(Control.iso, IntentField.iso))
        _ControlChip(
          key: const Key('control-iso'),
          label: 'ISO',
          value: settings?.iso?.toString() ?? 'Auto',
          auto: settings?.iso == null,
          onTap: () => _sheet(const _IsoSheet()),
          adjusted: state.result?.adjustmentFor(IntentField.iso) != null,
        ),
      if (showManual && shown(Control.shutter, IntentField.exposureTime))
        _ControlChip(
          key: const Key('control-shutter'),
          label: 'Shutter',
          value: settings?.exposureTimeNs == null
              ? 'Auto'
              : formatShutterNs(settings!.exposureTimeNs!),
          auto: settings?.exposureTimeNs == null,
          onTap: () => _sheet(const _ShutterSheet()),
          adjusted:
              state.result?.adjustmentFor(IntentField.exposureTime) != null,
        ),
      if (showManual && shown(Control.exposureBias, IntentField.exposureBias))
        _ControlChip(
          key: const Key('control-ev'),
          label: 'EV',
          value: formatEv(settings?.exposureBiasEv ?? 0),
          auto: (settings?.exposureBiasEv ?? 0) == 0,
          onTap: () => _sheet(const _EvSheet()),
        ),
      if (showManual &&
          (shown(Control.whiteBalancePresets, IntentField.whiteBalance) ||
              shown(Control.whiteBalanceKelvin, IntentField.whiteBalance)))
        _ControlChip(
          key: const Key('control-wb'),
          label: 'WB',
          value: settings == null
              ? 'Auto'
              : (settings.whiteBalance.kelvin != null
                    ? '${settings.whiteBalance.kelvin} K'
                    : presetLabel(settings.whiteBalance.preset)),
          auto:
              settings?.whiteBalance.preset == WbPreset.auto &&
              settings?.whiteBalance.kelvin == null,
          onTap: () => _sheet(const _WbSheet()),
        ),
      if (showManual &&
          (shown(Control.manualFocus, IntentField.manualFocus) ||
              shown(Control.focusLock, IntentField.focusLock)))
        _ControlChip(
          key: const Key('control-focus'),
          label: 'Focus',
          value: settings?.focusMode == FocusMode.manual
              ? 'Manual'
              : (settings?.focusLocked ?? false)
              ? 'Locked'
              : 'Auto',
          auto: settings?.focusMode != FocusMode.manual,
          onTap: () => _sheet(const _FocusSheet()),
        ),
      if (showManual && shown(Control.exposureLock, IntentField.exposureLock))
        _ControlChip(
          key: const Key('control-ae-lock'),
          label: 'AE lock',
          value: (settings?.exposureLocked ?? false) ? 'On' : 'Off',
          auto: !(settings?.exposureLocked ?? false),
          onTap: () => controller.adjust(
            (u) => u.merge(
              CaptureIntent(exposureLock: !(settings?.exposureLocked ?? false)),
            ),
          ),
        ),
      if (availability[Control.aperture] != null &&
          availability[Control.aperture]!.state == ControlState.readOnly &&
          state.pluginCaps?.apertures.isNotEmpty == true)
        _ReadoutChip(
          key: const Key('readout-aperture'),
          label: 'Aperture',
          value: 'ƒ/${state.pluginCaps!.apertures.first}',
        ),
      if (shown(Control.photoFormat, IntentField.photoFormat))
        _ControlChip(
          key: const Key('control-format'),
          label: 'Format',
          value: settings?.photoFormat?.name.toUpperCase() ?? 'JPEG',
          onTap: () => _sheet(const _FormatSheet()),
        ),
      if (state.caps.zoom.opticalSteps.length > 1 || backLenses.length > 1)
        if (backLenses.length > 1)
          _ControlChip(
            key: const Key('control-lens'),
            label: 'Lens',
            value: lensLabel(
              (state.camera?.lensKind ?? cam.LensKind.wide).name,
            ),
            onTap: () => _sheet(const _LensSheet()),
          ),
    ];

    return Material(
      color: Color(state.experience.theme.surface).withValues(alpha: 0.92),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: Color(state.experience.theme.onSurface)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 52,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: <Widget>[
                    ActionChip(
                      key: const Key('chip-scenario'),
                      avatar: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        state.scenario == null
                            ? 'Scenario'
                            : state.scenario!.name,
                      ),
                      onPressed: () => _sheet(const ScenarioSheet()),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      key: const Key('chip-preset'),
                      avatar: const Icon(Icons.bookmark_outline, size: 18),
                      label: Text(
                        state.preset == null ? 'Presets' : state.preset!.name,
                      ),
                      onPressed: () => _sheet(const PresetSheet()),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      key: const Key('chip-look'),
                      avatar: const Icon(
                        Icons.filter_vintage_outlined,
                        size: 18,
                      ),
                      label: Text(
                        'Look: ${ref.watch(profileRegistryProvider).resolve(settings?.profileId).name}',
                      ),
                      onPressed: () => _sheet(const LookSheet()),
                    ),
                    const SizedBox(width: 8),
                    if (!state.experience.workflow.manualDialsVisible)
                      FilterChip(
                        key: const Key('chip-manual-toggle'),
                        label: const Text('Manual controls'),
                        selected: showManual,
                        onSelected: (v) => setState(() => _manualOverride = v),
                      ),
                    if (state.user != CaptureIntent.empty &&
                        (state.user.specifiedFields.any(
                          (f) => f != IntentField.live,
                        )))
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ActionChip(
                          key: const Key('chip-reset'),
                          label: Text(
                            state.preset != null
                                ? 'Reset to preset'
                                : state.scenario != null
                                ? 'Reset to scenario'
                                : 'Reset',
                          ),
                          onPressed: controller.resetOverrides,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 64,
              child: SingleChildScrollView(
                key: const Key('control-strip'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: <Widget>[
                    for (final chip in chips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: chip,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        key: const Key('why-unavailable'),
                        tooltip: 'Why can’t I change…?',
                        onPressed: () => _sheet(const UnavailableSheet()),
                        icon: const Icon(Icons.help_outline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const ExperienceStrip(),
          ],
        ),
      ),
    );
  }

  void _sheet(Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.auto = false,
    this.adjusted = false,
  });

  final String label;
  final String value;
  final bool auto;
  final bool adjusted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '$label, $value${auto ? ', automatic' : ''}${adjusted ? ', adjusted for this camera' : ''}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (auto)
                      const Text(
                        'A ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: auto ? Theme.of(context).disabledColor : null,
                      ),
                    ),
                    if (adjusted) const Icon(Icons.info_outline, size: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadoutChip extends StatelessWidget {
  const _ReadoutChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value, fixed on this camera',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

/// Choose the camera body (EXP-001): one tap, restored at the next launch.
class ExperienceStrip extends ConsumerWidget {
  const ExperienceStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        key: const Key('experience-strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: <Widget>[
            for (final experience in Experiences.all)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('experience-${experience.id.name}'),
                  label: Text(experience.name),
                  selected: experience.id == state.experience.id,
                  onSelected: (_) => ref
                      .read(cameraControllerProvider.notifier)
                      .setExperience(experience),
                ),
              ),
            if (state.experience.workflow.showsFrameCounter)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Center(
                  child: Text(
                    'Frame ${state.framesShot}${state.experience.rollSize == null ? '' : ' / ${state.experience.rollSize}'}',
                    key: const Key('frame-counter'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- sheets ----------------------------------------------------------------------------------

class _SheetFrame extends ConsumerWidget {
  const _SheetFrame({
    required this.title,
    required this.field,
    required this.children,
    this.onAuto,
    this.autoLabel = 'Auto',
  });

  final String title;
  final IntentField? field;
  final List<Widget> children;
  final VoidCallback? onAuto;
  final String autoLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjustment = field == null
        ? null
        : ref.watch(cameraControllerProvider).result?.adjustmentFor(field!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (onAuto != null)
              TextButton(
                key: const Key('sheet-auto'),
                onPressed: onAuto,
                child: Text(autoLabel),
              ),
          ],
        ),
        ...children,
        if (adjustment != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    adjustment.message,
                    key: const Key('adjustment-message'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IsoSheet extends ConsumerWidget {
  const _IsoSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final range = state.caps.iso;
    if (range == null) {
      return const SizedBox.shrink();
    }
    final stops = isoStops(range);
    final current = state.settings?.iso;
    final index = current == null
        ? 0
        : stops.indexWhere((s) => s >= current).clamp(0, stops.length - 1);
    return _SheetFrame(
      title: 'ISO',
      field: IntentField.iso,
      onAuto: () => ref
          .read(cameraControllerProvider.notifier)
          .adjust((u) => u.without(<IntentField>{IntentField.iso})),
      children: <Widget>[
        Text(
          current == null ? 'Auto' : 'ISO $current',
          key: const Key('sheet-value'),
        ),
        Slider(
          key: const Key('slider-iso'),
          value: index.toDouble(),
          max: (stops.length - 1).toDouble(),
          divisions: stops.length > 1 ? stops.length - 1 : null,
          label: '${stops[index]}',
          semanticFormatterCallback: (v) => 'ISO ${stops[v.round()]}',
          onChanged: (v) => ref
              .read(cameraControllerProvider.notifier)
              .adjust((u) => u.merge(CaptureIntent(iso: stops[v.round()]))),
        ),
      ],
    );
  }
}

class _ShutterSheet extends ConsumerWidget {
  const _ShutterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final range = state.caps.exposureTimeNs;
    if (range == null) {
      return const SizedBox.shrink();
    }
    final stops = shutterStops(range);
    final current = state.settings?.exposureTimeNs;
    final index = current == null
        ? 0
        : stops.indexWhere((s) => s >= current).clamp(0, stops.length - 1);
    return _SheetFrame(
      title: 'Shutter speed',
      field: IntentField.exposureTime,
      onAuto: () => ref
          .read(cameraControllerProvider.notifier)
          .adjust((u) => u.without(<IntentField>{IntentField.exposureTime})),
      children: <Widget>[
        Text(
          current == null ? 'Auto' : formatShutterNs(current),
          key: const Key('sheet-value'),
        ),
        Slider(
          key: const Key('slider-shutter'),
          value: index.toDouble(),
          max: (stops.length - 1).toDouble(),
          divisions: stops.length > 1 ? stops.length - 1 : null,
          label: formatShutterNs(stops[index]),
          semanticFormatterCallback: (v) =>
              'Shutter ${formatShutterNs(stops[v.round()])}',
          onChanged: (v) => ref
              .read(cameraControllerProvider.notifier)
              .adjust(
                (u) => u.merge(CaptureIntent(exposureTimeNs: stops[v.round()])),
              ),
        ),
      ],
    );
  }
}

class _EvSheet extends ConsumerWidget {
  const _EvSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final caps = state.caps.exposureBias;
    if (caps == null) {
      return const SizedBox.shrink();
    }
    final value = state.settings?.exposureBiasEv ?? 0;
    final steps = ((caps.range.max - caps.range.min) / caps.step).round();
    return _SheetFrame(
      title: 'Exposure compensation',
      field: IntentField.exposureBias,
      onAuto: () => ref
          .read(cameraControllerProvider.notifier)
          .adjust((u) => u.without(<IntentField>{IntentField.exposureBias})),
      autoLabel: 'Reset',
      children: <Widget>[
        Text(formatEv(value), key: const Key('sheet-value')),
        Slider(
          key: const Key('slider-ev'),
          value: value.clamp(caps.range.min, caps.range.max),
          min: caps.range.min,
          max: caps.range.max,
          divisions: steps > 0 ? steps : null,
          label: formatEv(value),
          semanticFormatterCallback: formatEv,
          onChanged: (v) => ref
              .read(cameraControllerProvider.notifier)
              .adjust((u) => u.merge(CaptureIntent(exposureBiasEv: v))),
        ),
      ],
    );
  }
}

class _WbSheet extends ConsumerWidget {
  const _WbSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final caps = state.caps.whiteBalance;
    final wb = state.settings?.whiteBalance;
    final kelvin = caps.kelvin;
    final controller = ref.read(cameraControllerProvider.notifier);
    return _SheetFrame(
      title: 'White balance',
      field: IntentField.whiteBalance,
      onAuto: () => controller.adjust(
        (u) => u.without(<IntentField>{IntentField.whiteBalance}),
      ),
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final preset in WbPreset.values.where(caps.presets.contains))
              ChoiceChip(
                key: Key('wb-${preset.name}'),
                label: Text(presetLabel(preset)),
                selected:
                    wb != null && wb.kelvin == null && wb.preset == preset,
                onSelected: (_) => controller.adjust(
                  (u) => u.merge(
                    CaptureIntent(whiteBalance: WbRequest.preset(preset)),
                  ),
                ),
              ),
          ],
        ),
        if (kelvin != null && kelvin.isValid) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '${wb?.kelvin ?? 'Preset'}${wb?.kelvin != null ? ' K' : ''}',
            key: const Key('sheet-value'),
          ),
          Slider(
            key: const Key('slider-kelvin'),
            value: (wb?.kelvin ?? 5500)
                .clamp(kelvin.min, kelvin.max)
                .toDouble(),
            min: kelvin.min.toDouble(),
            max: kelvin.max.toDouble(),
            divisions: ((kelvin.max - kelvin.min) / 100).round().clamp(1, 200),
            label: '${wb?.kelvin ?? 5500} K',
            onChanged: (v) => controller.adjust(
              (u) => u.merge(
                CaptureIntent(
                  whiteBalance: WbRequest.kelvin((v / 100).round() * 100),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FocusSheet extends ConsumerWidget {
  const _FocusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final caps = state.caps.focus;
    final settings = state.settings;
    final controller = ref.read(cameraControllerProvider.notifier);
    final manual = caps.manual;
    final diopters = settings?.manualFocusDiopters ?? 0;
    return _SheetFrame(
      title: 'Focus',
      field: IntentField.manualFocus,
      onAuto: () => controller.adjust(
        (u) => u.without(<IntentField>{
          IntentField.focusMode,
          IntentField.manualFocus,
        }),
      ),
      children: <Widget>[
        if (caps.auto)
          SwitchListTile(
            key: const Key('switch-af-lock'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Lock focus'),
            value: settings?.focusLocked ?? false,
            onChanged: (v) =>
                controller.adjust((u) => u.merge(CaptureIntent(focusLock: v))),
          ),
        if (manual != null) ...<Widget>[
          SwitchListTile(
            key: const Key('switch-manual-focus'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Manual focus'),
            value: settings?.focusMode == FocusMode.manual,
            onChanged: (v) => controller.adjust(
              (u) => v
                  ? u.merge(const CaptureIntent(focus: FocusRequest.manual))
                  : u
                        .merge(
                          CaptureIntent(
                            focus: caps.continuous
                                ? FocusRequest.continuous
                                : FocusRequest.auto,
                          ),
                        )
                        .without(<IntentField>{IntentField.manualFocus}),
            ),
          ),
          if (settings?.focusMode == FocusMode.manual) ...<Widget>[
            // The distance is only named when the device says its focus is calibrated (CAM-021).
            Text(
              manual.canLabelDistance
                  ? formatFocusDistance(diopters)
                  : 'Near ⟷ far (not calibrated)',
              key: const Key('sheet-value'),
            ),
            Slider(
              key: const Key('slider-focus'),
              value: diopters.clamp(0, manual.minFocusDistanceDiopters),
              max: manual.minFocusDistanceDiopters,
              semanticFormatterCallback: (v) => manual.canLabelDistance
                  ? formatFocusDistance(v)
                  : 'Focus position ${(v / manual.minFocusDistanceDiopters * 100).round()} percent',
              onChanged: (v) => controller.adjust(
                (u) => u.merge(
                  CaptureIntent(
                    focus: FocusRequest.manual,
                    manualFocusDiopters: v,
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ZoomSheet extends ConsumerWidget {
  const _ZoomSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final zoom = state.caps.zoom;
    final value = state.settings?.zoom ?? 1;
    final controller = ref.read(cameraControllerProvider.notifier);
    return _SheetFrame(
      title: 'Zoom',
      field: IntentField.zoom,
      onAuto: () =>
          controller.adjust((u) => u.merge(const CaptureIntent(zoom: 1))),
      autoLabel: '1×',
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final step in zoom.opticalSteps)
              ChoiceChip(
                key: Key('zoom-step-$step'),
                label: Text(formatZoom(step)),
                selected: (value - step).abs() < 0.05,
                onSelected: (_) => controller.adjust(
                  (u) => u.merge(CaptureIntent(zoom: step)),
                ),
              ),
          ],
        ),
        Text(
          state.settings?.digitalZoom ?? false
              ? '${formatZoom(value)} (digital zoom: the picture is cropped and enlarged)'
              : formatZoom(value),
          key: const Key('sheet-value'),
        ),
        if (zoom.canZoom)
          Slider(
            key: const Key('slider-zoom'),
            value: value.clamp(zoom.min, zoom.max),
            min: zoom.min,
            max: zoom.max,
            label: formatZoom(value),
            semanticFormatterCallback: formatZoom,
            onChanged: (v) => controller.adjust(
              (u) => u.merge(
                CaptureIntent(zoom: double.parse(v.toStringAsFixed(1))),
              ),
            ),
          ),
      ],
    );
  }
}

class _FormatSheet extends ConsumerWidget {
  const _FormatSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final controller = ref.read(cameraControllerProvider.notifier);
    return _SheetFrame(
      title: 'Photo format',
      field: IntentField.photoFormat,
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final format in state.caps.photoFormats)
              ChoiceChip(
                key: Key('format-${format.name}'),
                label: Text(format.name.toUpperCase()),
                selected: state.settings?.photoFormat == format,
                onSelected: (_) => controller.adjust(
                  (u) => u.merge(CaptureIntent(photoFormat: format)),
                ),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('A new format takes effect when the camera restarts.'),
        ),
      ],
    );
  }
}

class _LensSheet extends ConsumerWidget {
  const _LensSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final controller = ref.read(cameraControllerProvider.notifier);
    final lenses = state.cameras
        .where(
          (c) =>
              c.facing == cam.CameraFacing.back &&
              c.source == state.camera?.source,
        )
        .toList();
    return _SheetFrame(
      title: 'Lens',
      field: null,
      children: <Widget>[
        for (final lens in lenses)
          RadioListTile<String>(
            key: Key('lens-${lens.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(lens.label),
            subtitle: Text(
              lens.focalLength35mmEq == null
                  ? lensLabel(lens.lensKind.name)
                  : '${lensLabel(lens.lensKind.name)} · ${lens.focalLength35mmEq!.round()} mm equivalent',
            ),
            value: lens.id,
            // ignore: deprecated_member_use
            groupValue: state.camera?.id,
            // ignore: deprecated_member_use
            onChanged: (_) {
              controller.selectCamera(lens);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}

/// "Not available on this camera", with a reason for each absent control (CAM-005).
class UnavailableSheet extends ConsumerWidget {
  const UnavailableSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final reasons = unavailableControls(state.caps);
    return Column(
      key: const Key('unavailable-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Not available on this camera',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (reasons.isEmpty && state.disabled.isEmpty)
          const Text('Everything the app offers is available on this camera.'),
        for (final entry in reasons.entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block, size: 18),
            title: Text(entry.value, key: Key('reason-${entry.key.name}')),
          ),
        for (final field in state.disabled)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber, size: 18),
            title: Text(
              '${field.name}: this camera ignored the setting three times, so it is off for this session.',
            ),
          ),
      ],
    );
  }
}

class ScenarioSheet extends ConsumerWidget {
  const ScenarioSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final controller = ref.read(cameraControllerProvider.notifier);
    final selected = state.scenario;
    return Column(
      key: const Key('scenario-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Assisted mode', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'Pick what you are shooting and Doro Cam suggests the settings, and tells you why.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            ChoiceChip(
              key: const Key('scenario-none'),
              label: const Text('None'),
              selected: selected == null,
              onSelected: (_) => controller.setScenario(null),
            ),
            for (final scenario in Scenarios.all)
              ChoiceChip(
                key: Key('scenario-${scenario.id.name}'),
                label: Text(scenario.name),
                selected: selected?.id == scenario.id,
                onSelected: (_) => controller.setScenario(scenario),
              ),
          ],
        ),
        if (selected != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            selected.summary,
            key: const Key('scenario-summary'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          for (final explanation in selected.explanations.values)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $explanation'),
            ),
        ],
      ],
    );
  }
}

class PresetSheet extends ConsumerWidget {
  const PresetSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final controller = ref.read(cameraControllerProvider.notifier);
    final presets = ref.watch(presetsProvider).value ?? const [];
    final rows = presets
        .where(
          (p) =>
              p.deletedAt == null && p.experienceId == state.experience.id.name,
        )
        .toList();
    return Column(
      key: const Key('preset-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Presets', style: Theme.of(context).textTheme.titleMedium),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No presets for this camera yet. Set it up how you like, then save it.',
            ),
          ),
        for (final row in rows)
          ListTile(
            key: Key('preset-${row.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(row.name),
            trailing: state.preset?.id == row.id
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              controller.setPreset(rowToPreset(row));
              Navigator.of(context).pop();
            },
          ),
        if (state.preset != null)
          TextButton(
            key: const Key('preset-clear'),
            onPressed: () => controller.setPreset(null),
            child: const Text('Stop using preset'),
          ),
        const Divider(),
        FilledButton.icon(
          key: const Key('preset-save'),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save current settings as preset'),
          onPressed: () => _saveDialog(context, controller),
        ),
      ],
    );
  }

  Future<void> _saveDialog(
    BuildContext context,
    CameraController controller,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _PresetNameDialog(),
    );
    if (result != null && result.isNotEmpty) {
      await controller.saveAsPreset(result);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

/// Owns its text controller, so it is disposed only after the dialog has fully left the screen.
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save preset'),
      content: TextField(
        key: const Key('preset-name'),
        controller: _name,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Preset name'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('preset-name-save'),
          onPressed: () => Navigator.pop(context, _name.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class LookSheet extends ConsumerWidget {
  const LookSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraControllerProvider);
    final registry = ref.watch(profileRegistryProvider);
    final current = registry.resolve(state.settings?.profileId);
    return Column(
      key: const Key('look-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Look', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'Looks are original film-inspired recipes. The viewfinder shows the look live; your original photo is always kept untouched.',
        ),
        const SizedBox(height: 8),
        for (final profile in registry.latest)
          RadioListTile<String>(
            key: Key('look-${profile.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(profile.name),
            subtitle: Text(profile.description),
            value: profile.id,
            // ignore: deprecated_member_use
            groupValue: current.id,
            // ignore: deprecated_member_use
            onChanged: (value) {
              if (value != null) {
                ref.read(cameraControllerProvider.notifier).setProfile(value);
              }
            },
          ),
      ],
    );
  }
}
