import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/community_provider.dart';
import '../widgets/common.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Комьюнити')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: () => _createPost(context, ref),
        child: const Icon(Icons.edit_outlined),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(feedProvider.notifier).reload(),
        child: feed.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(apiErrorMessage(e), textAlign: TextAlign.center),
              ),
            ],
          ),
          data: (posts) => posts.isEmpty
              ? ListView(
                  children: const [_EmptyFeed()],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  itemCount: posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, i) => _PostCard(post: posts[i]),
                ),
        ),
      ),
    );
  }

  Future<void> _createPost(BuildContext context, WidgetRef ref) async {
    final textCtrl = TextEditingController();
    XFile? photo;

    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Новый пост',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              if (photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(File(photo!.path),
                      height: 160, width: double.infinity, fit: BoxFit.cover),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'Расскажите о своих джунглях…'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 16)),
                    onPressed: () async {
                      final picked = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1600,
                          imageQuality: 88);
                      if (picked != null) setSheetState(() => photo = picked);
                    },
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('Фото'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46)),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: const Text('Опубликовать'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (posted == true && textCtrl.text.trim().isNotEmpty) {
      await ref.read(feedProvider.notifier).createPost(
            text: textCtrl.text.trim(),
            image: photo != null
                ? await MultipartFile.fromFile(photo!.path, filename: 'post.jpg')
                : null,
          );
    }
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.secondaryContainer,
                backgroundImage: post.authorAvatarUrl != null
                    ? NetworkImage(ApiConfig.imageUrl(post.authorAvatarUrl))
                    : null,
                child: post.authorAvatarUrl == null
                    ? Text(
                        post.authorName.isNotEmpty
                            ? post.authorName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.authorName, style: theme.textTheme.titleMedium),
                  Text(
                    DateFormat('d MMMM, HH:mm', 'ru').format(post.createdAt),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(post.text, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.5)),
          if (post.imageUrl != null) ...[
            const SizedBox(height: 12),
            PlantImage(url: post.imageUrl, height: 220, width: double.infinity),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _ActionChip(
                icon: post.likedByMe ? Icons.favorite : Icons.favorite_border,
                label: '${post.likesCount}',
                color: post.likedByMe ? AppColors.terracotta : AppColors.outline,
                onTap: () =>
                    ref.read(feedProvider.notifier).toggleLike(post.id),
              ),
              const SizedBox(width: 10),
              _ActionChip(
                icon: Icons.mode_comment_outlined,
                label: '${post.commentsCount}',
                color: AppColors.outline,
                onTap: () => _openComments(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openComments(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CommentsSheet(postId: post.id),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.postId});

  final String postId;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final api = ref.read(apiProvider);
      await api.dio
          .post('/api/community/posts/${widget.postId}/comments', data: {'text': text});
      _ctrl.clear();
      ref.invalidate(commentsProvider(widget.postId));
      await ref.read(feedProvider.notifier).reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(commentsProvider(widget.postId));
    final theme = Theme.of(context);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
              child: Text('Комментарии', style: theme.textTheme.headlineMedium),
            ),
            Expanded(
              child: comments.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(child: Text(apiErrorMessage(e))),
                data: (items) => items.isEmpty
                    ? Center(
                        child: Text('Будьте первым, кто ответит 🌱',
                            style: theme.textTheme.bodyMedium),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final c = items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 15,
                                  backgroundColor: AppColors.secondaryContainer,
                                  child: Text(
                                    c.authorName.isNotEmpty
                                        ? c.authorName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(c.authorName,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(fontSize: 14.5)),
                                      Text(c.text,
                                          style: theme.textTheme.bodyMedium),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        decoration:
                            const InputDecoration(hintText: 'Ваш комментарий…'),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(50, 50),
                      ),
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send, size: 20, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
      child: Column(
        children: [
          const Icon(Icons.forum_outlined, size: 56, color: AppColors.outline),
          const SizedBox(height: 18),
          Text('Здесь пока тихо', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Поделитесь первым фото своих джунглей — комьюнити оценит!',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
