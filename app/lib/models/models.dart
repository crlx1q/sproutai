class User {
  User({
    required this.id,
    required this.email,
    required this.name,
    this.avatarUrl,
    required this.plan,
    required this.role,
    required this.scansUsed,
  });

  final String id;
  final String email;
  final String name;
  final String? avatarUrl;
  final String plan;
  final String role;
  final int scansUsed;

  bool get isPro => plan == 'pro';

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        plan: (json['plan'] ?? 'free') as String,
        role: (json['role'] ?? 'user') as String,
        scansUsed: (json['scansUsed'] ?? 0) as int,
      );
}

class PlantCare {
  PlantCare({
    required this.wateringIntervalDays,
    required this.waterAmountMl,
    required this.light,
    required this.fertilizerIntervalDays,
    required this.temperature,
    this.checkupIntervalDays = 14,
  });

  final int wateringIntervalDays;
  final int waterAmountMl;
  final String light;
  final int fertilizerIntervalDays;
  final String temperature;
  final int checkupIntervalDays;

  factory PlantCare.fromJson(Map<String, dynamic>? json) => PlantCare(
        wateringIntervalDays: (json?['wateringIntervalDays'] ?? 7) as int,
        waterAmountMl: (json?['waterAmountMl'] ?? 250) as int,
        light: (json?['light'] ?? 'Непрямой свет') as String,
        fertilizerIntervalDays: (json?['fertilizerIntervalDays'] ?? 30) as int,
        temperature: (json?['temperature'] ?? '18-24°C') as String,
        checkupIntervalDays: (json?['checkupIntervalDays'] ?? 14) as int,
      );

  Map<String, dynamic> toJson() => {
        'wateringIntervalDays': wateringIntervalDays,
        'waterAmountMl': waterAmountMl,
        'light': light,
        'fertilizerIntervalDays': fertilizerIntervalDays,
        'temperature': temperature,
        'checkupIntervalDays': checkupIntervalDays,
      };
}

class Diagnosis {
  Diagnosis({
    required this.isHealthy,
    required this.title,
    required this.description,
    required this.confidence,
    required this.treatmentPlan,
    this.scannedAt,
  });

  final bool isHealthy;
  final String title;
  final String description;
  final double confidence;
  final List<String> treatmentPlan;
  final DateTime? scannedAt;

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
        isHealthy: (json['isHealthy'] ?? true) as bool,
        title: (json['title'] ?? '') as String,
        description: (json['description'] ?? '') as String,
        confidence: ((json['confidence'] ?? 0) as num).toDouble(),
        treatmentPlan: ((json['treatmentPlan'] ?? []) as List).cast<String>(),
        scannedAt: json['scannedAt'] != null
            ? DateTime.tryParse(json['scannedAt'] as String)
            : null,
      );
}

class Plant {
  Plant({
    required this.id,
    required this.name,
    required this.species,
    required this.location,
    this.photoUrl,
    required this.healthStatus,
    required this.healthScore,
    required this.care,
    this.lastWateredAt,
    this.lastFertilizedAt,
    this.lastDiagnosis,
    this.wateringDueAt,
    this.fertilizingDueAt,
    required this.needsWater,
    this.needsFertilizer = false,
    this.origin = 'existing',
    this.stage = 'mature',
    this.plantedAt,
    this.growthGoal = '',
    this.checkupDueAt,
    this.needsCheckup = false,
  });

  final String id;
  final String name;
  final String species;
  final String location;
  final String? photoUrl;
  final String healthStatus;
  final int healthScore;
  final PlantCare care;
  final DateTime? lastWateredAt;
  final DateTime? lastFertilizedAt;
  final Diagnosis? lastDiagnosis;
  final DateTime? wateringDueAt;
  final DateTime? fertilizingDueAt;
  final bool needsWater;
  final bool needsFertilizer;
  final String origin;
  final String stage;
  final DateTime? plantedAt;
  final String growthGoal;
  final DateTime? checkupDueAt;
  final bool needsCheckup;

  bool get isGrown => origin == 'grown';

  factory Plant.fromJson(Map<String, dynamic> json) => Plant(
        id: json['_id'] as String,
        name: json['name'] as String,
        species: (json['species'] ?? '') as String,
        location: (json['location'] ?? 'indoor') as String,
        photoUrl: json['photoUrl'] as String?,
        healthStatus: (json['healthStatus'] ?? 'thriving') as String,
        healthScore: (json['healthScore'] ?? 90) as int,
        care: PlantCare.fromJson(json['care'] as Map<String, dynamic>?),
        lastWateredAt: json['lastWateredAt'] != null
            ? DateTime.tryParse(json['lastWateredAt'] as String)
            : null,
        lastFertilizedAt: json['lastFertilizedAt'] != null
            ? DateTime.tryParse(json['lastFertilizedAt'] as String)
            : null,
        lastDiagnosis: json['lastDiagnosis'] != null
            ? Diagnosis.fromJson(json['lastDiagnosis'] as Map<String, dynamic>)
            : null,
        wateringDueAt: json['wateringDueAt'] != null
            ? DateTime.tryParse(json['wateringDueAt'] as String)
            : null,
        fertilizingDueAt: json['fertilizingDueAt'] != null
            ? DateTime.tryParse(json['fertilizingDueAt'] as String)
            : null,
        needsWater: (json['needsWater'] ?? false) as bool,
        needsFertilizer: (json['needsFertilizer'] ?? false) as bool,
        origin: (json['origin'] ?? 'existing') as String,
        stage: (json['stage'] ?? 'mature') as String,
        plantedAt: json['plantedAt'] != null
            ? DateTime.tryParse(json['plantedAt'] as String)
            : null,
        growthGoal: (json['growthGoal'] ?? '') as String,
        checkupDueAt: json['checkupDueAt'] != null
            ? DateTime.tryParse(json['checkupDueAt'] as String)
            : null,
        needsCheckup: (json['needsCheckup'] ?? false) as bool,
      );
}

class JournalEntry {
  JournalEntry({
    required this.id,
    this.photoUrl,
    required this.note,
    required this.kind,
    required this.createdAt,
    this.healthScore,
    this.healthStatus,
    this.analysis,
    this.trend,
  });

  final String id;
  final String? photoUrl;
  final String note;
  final String kind;
  final DateTime createdAt;
  final int? healthScore;
  final String? healthStatus;
  final String? analysis;
  final String? trend;

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['_id'] as String,
        photoUrl: json['photoUrl'] as String?,
        note: (json['note'] ?? '') as String,
        kind: (json['kind'] ?? 'progress') as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        healthScore: (json['healthScore'] as num?)?.toInt(),
        healthStatus: json['healthStatus'] as String?,
        analysis: json['analysis'] as String?,
        trend: json['trend'] as String?,
      );
}

class Reminder {
  Reminder({
    required this.id,
    required this.plantId,
    required this.type,
    required this.intervalDays,
    required this.nextDueAt,
    required this.active,
  });

  final String id;
  final String plantId;
  final String type;
  final int intervalDays;
  final DateTime nextDueAt;
  final bool active;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['_id'] as String,
        plantId: json['plantId'] as String,
        type: json['type'] as String,
        intervalDays: (json['intervalDays'] ?? 7) as int,
        nextDueAt: DateTime.parse(json['nextDueAt'] as String),
        active: (json['active'] ?? true) as bool,
      );
}

class ScanCareAdvice {
  ScanCareAdvice({
    required this.wateringIntervalDays,
    required this.waterAmountMl,
    required this.watering,
    required this.light,
    required this.fertilizer,
    required this.fertilizerIntervalDays,
    required this.temperature,
  });

  final int wateringIntervalDays;
  final int waterAmountMl;
  final String watering;
  final String light;
  final String fertilizer;
  final int fertilizerIntervalDays;
  final String temperature;

  factory ScanCareAdvice.fromJson(Map<String, dynamic>? json) => ScanCareAdvice(
        wateringIntervalDays: (json?['wateringIntervalDays'] ?? 7) as int,
        waterAmountMl: (json?['waterAmountMl'] ?? 250) as int,
        watering: (json?['watering'] ?? '') as String,
        light: (json?['light'] ?? '') as String,
        fertilizer: (json?['fertilizer'] ?? '') as String,
        fertilizerIntervalDays: (json?['fertilizerIntervalDays'] ?? 30) as int,
        temperature: (json?['temperature'] ?? '18-24°C') as String,
      );
}

class ScanOutcome {
  ScanOutcome({
    required this.scanId,
    required this.imageUrl,
    required this.isPlant,
    required this.species,
    required this.commonName,
    required this.isHealthy,
    required this.healthScore,
    required this.diagnosisTitle,
    required this.diagnosisDescription,
    required this.confidence,
    required this.treatmentPlan,
    required this.careAdvice,
    required this.progressNote,
    this.scansRemaining,
  });

  final String scanId;
  final String imageUrl;
  final bool isPlant;
  final String species;
  final String commonName;
  final bool isHealthy;
  final int healthScore;
  final String diagnosisTitle;
  final String diagnosisDescription;
  final double confidence;
  final List<String> treatmentPlan;
  final ScanCareAdvice careAdvice;
  final String progressNote;
  final int? scansRemaining;

  factory ScanOutcome.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>;
    final diagnosis = (result['diagnosis'] ?? {}) as Map<String, dynamic>;
    return ScanOutcome(
      scanId: json['scanId'] as String,
      imageUrl: json['imageUrl'] as String,
      isPlant: (result['isPlant'] ?? false) as bool,
      species: (result['species'] ?? '') as String,
      commonName: (result['commonName'] ?? '') as String,
      isHealthy: (result['isHealthy'] ?? true) as bool,
      healthScore: (result['healthScore'] ?? 0) as int,
      diagnosisTitle: (diagnosis['title'] ?? '') as String,
      diagnosisDescription: (diagnosis['description'] ?? '') as String,
      confidence: ((diagnosis['confidence'] ?? 0) as num).toDouble(),
      treatmentPlan: ((result['treatmentPlan'] ?? []) as List).cast<String>(),
      careAdvice:
          ScanCareAdvice.fromJson(result['careAdvice'] as Map<String, dynamic>?),
      progressNote: (result['progressNote'] ?? '') as String,
      scansRemaining: (json['quota']?['remaining']) as int?,
    );
  }
}

class Post {
  Post({
    required this.id,
    required this.authorName,
    this.authorAvatarUrl,
    this.imageUrl,
    required this.text,
    required this.likesCount,
    required this.likedByMe,
    required this.commentsCount,
    required this.createdAt,
  });

  final String id;
  final String authorName;
  final String? authorAvatarUrl;
  final String? imageUrl;
  final String text;
  final int likesCount;
  final bool likedByMe;
  final int commentsCount;
  final DateTime createdAt;

  Post copyWith({int? likesCount, bool? likedByMe, int? commentsCount}) => Post(
        id: id,
        authorName: authorName,
        authorAvatarUrl: authorAvatarUrl,
        imageUrl: imageUrl,
        text: text,
        likesCount: likesCount ?? this.likesCount,
        likedByMe: likedByMe ?? this.likedByMe,
        commentsCount: commentsCount ?? this.commentsCount,
        createdAt: createdAt,
      );

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        authorName: (json['author']?['name'] ?? 'Аноним') as String,
        authorAvatarUrl: json['author']?['avatarUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        text: json['text'] as String,
        likesCount: (json['likesCount'] ?? 0) as int,
        likedByMe: (json['likedByMe'] ?? false) as bool,
        commentsCount: (json['commentsCount'] ?? 0) as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class PostComment {
  PostComment({
    required this.id,
    required this.authorName,
    this.authorAvatarUrl,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String authorName;
  final String? authorAvatarUrl;
  final String text;
  final DateTime createdAt;

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: json['id'] as String,
        authorName: (json['author']?['name'] ?? 'Аноним') as String,
        authorAvatarUrl: json['author']?['avatarUrl'] as String?,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class ScanQuota {
  ScanQuota({required this.plan, this.limit, required this.used, this.remaining});

  final String plan;
  final int? limit;
  final int used;
  final int? remaining;

  bool get isUnlimited => remaining == null;

  factory ScanQuota.fromJson(Map<String, dynamic> json) => ScanQuota(
        plan: (json['plan'] ?? 'free') as String,
        limit: json['limit'] as int?,
        used: (json['used'] ?? 0) as int,
        remaining: json['remaining'] as int?,
      );
}
