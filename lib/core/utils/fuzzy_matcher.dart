class FuzzyMatcher {
  /// Strips accents and converts string to lowercase for normalized comparison.
  static String normalize(String str) {
    var normalized = str.toLowerCase();
    // Simple diacritic replacement
    normalized = normalized
        .replaceAll(RegExp(r'[áàâäãå]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôöõ]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[ç]'), 'c');
    return normalized;
  }

  /// Calculates the Levenshtein distance between two strings.
  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = _min3(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost);
      }
      v0 = List<int>.from(v1);
    }
    return v0[t.length];
  }

  static int _min3(int a, int b, int c) {
    int min = a;
    if (b < min) min = b;
    if (c < min) min = c;
    return min;
  }

  /// Calculates a Levenshtein similarity score between 0.0 and 1.0.
  static double levenshteinSimilarity(String s, String t) {
    final cleanS = normalize(s);
    final cleanT = normalize(t);
    if (cleanS.isEmpty && cleanT.isEmpty) return 1.0;
    final maxLen = cleanS.length > cleanT.length ? cleanS.length : cleanT.length;
    final dist = levenshtein(cleanS, cleanT);
    return 1.0 - (dist / maxLen);
  }

  /// Calculates Trigram similarity between two strings.
  static double trigramSimilarity(String s, String t) {
    final cleanS = normalize(s);
    final cleanT = normalize(t);
    
    final sTrigrams = _getTrigrams(cleanS);
    final tTrigrams = _getTrigrams(cleanT);
    
    if (sTrigrams.isEmpty || tTrigrams.isEmpty) {
      return cleanS.contains(cleanT) || cleanT.contains(cleanS) ? 0.3 : 0.0;
    }
    
    int intersection = 0;
    for (final tri in sTrigrams) {
      if (tTrigrams.contains(tri)) {
        intersection++;
      }
    }
    
    return (2.0 * intersection) / (sTrigrams.length + tTrigrams.length);
  }

  static Set<String> _getTrigrams(String str) {
    final trigrams = <String>{};
    if (str.length < 3) {
      if (str.isNotEmpty) trigrams.add(str);
      return trigrams;
    }
    for (int i = 0; i < str.length - 2; i++) {
      trigrams.add(str.substring(i, i + 3));
    }
    return trigrams;
  }

  /// Combined similarity score that values:
  /// 1. Exact contains match (highest boost)
  /// 2. Word prefix matches (important for typing "sill" to match "Silliman")
  /// 3. Trigram & Levenshtein similarity for typos
  static double getCombinedSimilarity(String query, String target) {
    final q = normalize(query.trim());
    final t = normalize(target.trim());

    if (q.isEmpty || t.isEmpty) return 0.0;
    if (q == t) return 1.0;

    // 1. Direct sub-string match checks
    if (t.contains(q)) {
      // Boost if it matches the start of the string or start of a word
      if (t.startsWith(q)) {
        return 0.9 + (q.length / t.length) * 0.1; // 0.9 - 1.0
      }
      final words = t.split(RegExp(r'\s+'));
      if (words.any((w) => w.startsWith(q))) {
        return 0.8 + (q.length / t.length) * 0.1; // 0.8 - 0.9
      }
      return 0.7 + (q.length / t.length) * 0.1; // 0.7 - 0.8
    }

    // 2. Word-by-word prefix checks (e.g. query "sill uni" matches "Silliman University")
    final qWords = q.split(RegExp(r'\s+'));
    final tWords = t.split(RegExp(r'\s+'));
    int matchingWords = 0;
    for (final qw in qWords) {
      if (tWords.any((tw) => tw.startsWith(qw))) {
        matchingWords++;
      }
    }
    if (matchingWords == qWords.length) {
      return 0.75;
    }

    // 3. Fuzzy matchers
    final trigram = trigramSimilarity(q, t);
    final lev = levenshteinSimilarity(q, t);
    
    // Weighted combination of trigram and Levenshtein
    final double fuzzyScore = (trigram * 0.6) + (lev * 0.4);
    
    return fuzzyScore;
  }
}
