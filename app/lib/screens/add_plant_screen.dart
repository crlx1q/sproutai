import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../providers/plants_provider.dart';

class AddPlantScreen extends ConsumerStatefulWidget {
  const AddPlantScreen({super.key});

  @override
  ConsumerState<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends ConsumerState<AddPlantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _species = TextEditingController();
  String _location = 'indoor';
  int _wateringDays = 7;
  bool _manualCare = false;
  XFile? _photo;
  bool _busy = false;
  String _origin = 'existing';
  String _stage = 'seedling';
  DateTime _plantedAt = DateTime.now();
  final _goal = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _species.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 88);
    if (picked != null) setState(() => _photo = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(plantsProvider.notifier).addPlant(
            name: _name.text.trim(),
            species: _species.text.trim(),
            location: _location,
            origin: _origin,
            stage: _origin == 'grown' ? _stage : null,
            plantedAt: _origin == 'grown' ? _plantedAt : null,
            growthGoal: _origin == 'grown' ? _goal.text.trim() : null,
            photo: _photo != null
                ? await MultipartFile.fromFile(_photo!.path, filename: 'plant.jpg')
                : null,
            care: _manualCare ? {'wateringIntervalDays': _wateringDays} : null,
          );
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('«${_name.text.trim()}» теперь в вашем саду 🌿')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Новое растение')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              GestureDetector(
                onTap: () => showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (sheetContext) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.photo_camera_outlined),
                          title: const Text('Сделать фото'),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _pickPhoto(ImageSource.camera);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.photo_library_outlined),
                          title: const Text('Выбрать из галереи'),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _pickPhoto(ImageSource.gallery);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppColors.mintSoft,
                    borderRadius: BorderRadius.circular(24),
                    image: _photo != null
                        ? DecorationImage(
                            image: FileImage(File(_photo!.path)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _photo == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined,
                                size: 40, color: AppColors.secondary),
                            const SizedBox(height: 10),
                            Text('Добавить фото',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.secondary)),
                          ],
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              _OriginSelector(
                origin: _origin,
                onChanged: (v) => setState(() => _origin = v),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Имя растения, например «Монстера»'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Дайте растению имя' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _species,
                decoration:
                    const InputDecoration(hintText: 'Вид (необязательно)'),
              ),
              const SizedBox(height: 24),
              Text('Где живёт', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Row(
                children: [
                  _LocationChip(
                    label: 'Комнатное',
                    icon: Icons.chair_outlined,
                    selected: _location == 'indoor',
                    onTap: () => setState(() => _location = 'indoor'),
                  ),
                  const SizedBox(width: 10),
                  _LocationChip(
                    label: 'Уличное',
                    icon: Icons.deck_outlined,
                    selected: _location == 'outdoor',
                    onTap: () => setState(() => _location = 'outdoor'),
                  ),
                ],
              ),
              if (_origin == 'grown') ...[
                const SizedBox(height: 24),
                Text('Стадия роста', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _stageOptions.entries)
                      ChoiceChip(
                        label: Text(s.value),
                        selected: _stage == s.key,
                        onSelected: (_) => setState(() => _stage = s.key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Посажено: ${DateFormat('d MMM y', 'ru').format(_plantedAt)}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _plantedAt,
                          firstDate: DateTime(2015),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => _plantedAt = picked);
                      },
                      child: const Text('Изменить'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _goal,
                  decoration: const InputDecoration(
                      hintText: 'Цель, например «зацвести к лету» (необязательно)'),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Настроить полив вручную',
                            style: theme.textTheme.titleMedium),
                        Text(
                          _manualCare
                              ? 'Раз в $_wateringDays дн.'
                              : 'ИИ подберёт график по фото и виду',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _manualCare,
                    onChanged: (v) => setState(() => _manualCare = v),
                  ),
                ],
              ),
              if (_manualCare)
                Slider(
                  value: _wateringDays.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  activeColor: AppColors.primary,
                  label: '$_wateringDays',
                  onChanged: (v) => setState(() => _wateringDays = v.round()),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Добавить в сад'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondaryContainer : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.secondary : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19,
                  color: selected ? AppColors.primary : AppColors.outline),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


const Map<String, String> _stageOptions = {
  'seed': 'Семя',
  'sprout': 'Росток',
  'seedling': 'Саженец',
  'growing': 'Растёт',
  'mature': 'Взрослое',
  'flowering': 'Цветёт',
};

class _OriginSelector extends StatelessWidget {
  const _OriginSelector({required this.origin, required this.onChanged});

  final String origin;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LocationChip(
          label: 'Уже есть',
          icon: Icons.eco_outlined,
          selected: origin == 'existing',
          onTap: () => onChanged('existing'),
        ),
        const SizedBox(width: 10),
        _LocationChip(
          label: 'Расту с нуля',
          icon: Icons.spa_outlined,
          selected: origin == 'grown',
          onTap: () => onChanged('grown'),
        ),
      ],
    );
  }
}
