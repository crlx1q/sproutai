import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, icon) = switch (status) {
      'thriving' => ('Отлично', AppColors.secondaryContainer, AppColors.secondary, Icons.favorite_border),
      'needs_attention' => ('Хочет пить', AppColors.terracottaContainer, AppColors.terracotta, Icons.water_drop_outlined),
      _ => ('Болеет', AppColors.terracottaContainer, AppColors.terracotta, Icons.healing_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

class PlantImage extends StatelessWidget {
  const PlantImage({super.key, this.url, this.height, this.width, this.radius = 16});

  final String? url;
  final double? height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.imageUrl(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: resolved.isEmpty
          ? Container(
              height: height,
              width: width,
              color: AppColors.mintSoft,
              child: const Center(
                child: Icon(Icons.local_florist_outlined,
                    size: 42, color: AppColors.secondary),
              ),
            )
          : CachedNetworkImage(
              imageUrl: resolved,
              height: height,
              width: width,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.mintSoft),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.mintSoft,
                child: const Icon(Icons.local_florist_outlined,
                    color: AppColors.secondary),
              ),
            ),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding, this.color, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: softShadow(),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}
