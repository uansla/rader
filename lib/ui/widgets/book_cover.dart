import 'package:flutter/material.dart';

import '../../models/book.dart';

class BookCover extends StatelessWidget {
  final Book book;
  final double width;
  final double height;

  const BookCover({
    super.key,
    required this.book,
    this.width = 72,
    this.height = 100,
  });

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(book);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text(
                  book.title.isNotEmpty ? book.title.characters.first : '书',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Icon(
              book.isAudio ? Icons.headphones : Icons.auto_stories,
              size: 14,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          if (book.isFavorite)
            const Positioned(
              left: 4,
              top: 4,
              child: Icon(Icons.star, size: 14, color: Colors.amber),
            ),
        ],
      ),
    );
  }

  static Color _resolveColor(Book book) {
    if (book.coverColor >= 0 && book.coverColor < kCoverColors.length) {
      return kCoverColors[book.coverColor];
    }
    return _colorFor(book.title);
  }

  static const List<Color> kCoverColors = [
    Color(0xFF5B8DB8),
    Color(0xFF7A6FA6),
    Color(0xFFB8775B),
    Color(0xFF5FA37E),
    Color(0xFFB58C3F),
    Color(0xFF7E5FA3),
    Color(0xFFB8606A),
    Color(0xFF4E9AA8),
  ];

  static Color _colorFor(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return kCoverColors[h % kCoverColors.length];
  }
}
