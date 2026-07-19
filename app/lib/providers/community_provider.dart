import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../models/models.dart';

final feedProvider = AsyncNotifierProvider<FeedNotifier, List<Post>>(FeedNotifier.new);

class FeedNotifier extends AsyncNotifier<List<Post>> {
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<List<Post>> build() => _fetch();

  Future<List<Post>> _fetch() async {
    final res = await _api.dio.get('/api/community/posts');
    return (res.data['posts'] as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> createPost({required String text, MultipartFile? image}) async {
    final form = FormData.fromMap({
      'text': text,
      if (image != null) 'image': image,
    });
    await _api.dio.post('/api/community/posts', data: form);
    await reload();
  }

  Future<void> toggleLike(String postId) async {
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data([
        for (final p in current)
          if (p.id == postId)
            p.copyWith(
              likedByMe: !p.likedByMe,
              likesCount: p.likesCount + (p.likedByMe ? -1 : 1),
            )
          else
            p
      ]);
    }
    try {
      await _api.dio.post('/api/community/posts/$postId/like');
    } catch (_) {
      await reload();
    }
  }
}

final commentsProvider = FutureProvider.autoDispose
    .family<List<PostComment>, String>((ref, postId) async {
  final api = ref.watch(apiProvider);
  final res = await api.dio.get('/api/community/posts/$postId/comments');
  return (res.data['comments'] as List)
      .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
      .toList();
});
