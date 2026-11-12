import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SnakeApp());
}

class SnakeApp extends StatelessWidget {
  const SnakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Змейка',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const GamePage(),
    );
  }
}

enum Dir { up, down, left, right }

bool _opposite(Dir a, Dir b) =>
    (a == Dir.up && b == Dir.down) ||
    (a == Dir.down && b == Dir.up) ||
    (a == Dir.left && b == Dir.right) ||
    (a == Dir.right && b == Dir.left);

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  static const int cols = 18;
  static const int rows = 26;

  final Random _rnd = Random();
  List<Point<int>> snake = [];
  Point<int> food = const Point(0, 0);
  Dir dir = Dir.right;
  final List<Dir> pending = [];
  Timer? timer;

  int score = 0;
  int best = 0;
  bool running = false;
  bool gameOver = false;
  bool won = false;
  bool started = false;

  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  // Ставим игру на паузу, если приложение свернули.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && running) _pause();
  }

  void _reset() {
    const y = rows ~/ 2;
    snake = [const Point(6, y), const Point(5, y), const Point(4, y)];
    dir = Dir.right;
    pending.clear();
    score = 0;
    gameOver = false;
    won = false;
    started = false;
    running = false;
    _placeFood();
  }

  void _placeFood() {
    final free = <Point<int>>[];
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < rows; y++) {
        final p = Point(x, y);
        if (!snake.contains(p)) free.add(p);
      }
    }
    if (free.isEmpty) {
      won = true;
      _endGame();
      return;
    }
    food = free[_rnd.nextInt(free.length)];
  }

  Duration get _speed => Duration(milliseconds: max(65, 190 - score * 4));

  void _start() {
    if (gameOver) _reset();
    started = true;
    running = true;
    _schedule();
    setState(() {});
  }

  void _pause() {
    running = false;
    timer?.cancel();
    setState(() {});
  }

  void _schedule() {
    timer?.cancel();
    timer = Timer(_speed, _tick);
  }

  void _endGame() {
    running = false;
    gameOver = true;
    timer?.cancel();
    if (score > best) best = score;
    HapticFeedback.heavyImpact();
  }

  void _tick() {
    if (!running) return;
    if (pending.isNotEmpty) dir = pending.removeAt(0);

    final h = snake.first;
    final next = switch (dir) {
      Dir.up => Point(h.x, h.y - 1),
      Dir.down => Point(h.x, h.y + 1),
      Dir.left => Point(h.x - 1, h.y),
      Dir.right => Point(h.x + 1, h.y),
    };

    final eats = next == food;
    final body = eats ? snake : snake.sublist(0, snake.length - 1);
    final hitWall =
        next.x < 0 || next.y < 0 || next.x >= cols || next.y >= rows;

    if (hitWall || body.contains(next)) {
      setState(_endGame);
      return;
    }

    snake.insert(0, next);
    if (eats) {
      score++;
      HapticFeedback.lightImpact();
      _placeFood();
      if (gameOver) {
        setState(() {});
        return;
      }
    } else {
      snake.removeLast();
    }
    setState(() {});
    _schedule();
  }

  void _turn(Dir d) {
    if (gameOver) return;
    final last = pending.isNotEmpty ? pending.last : dir;
    if (d == last || _opposite(d, last)) {
      if (!running) _start();
      return;
    }
    if (pending.length < 2) pending.add(d);
    if (!running) _start();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _drag += details.delta;
    const threshold = 18.0;
    if (_drag.distance < threshold) return;
    if (_drag.dx.abs() > _drag.dy.abs()) {
      _turn(_drag.dx > 0 ? Dir.right : Dir.left);
    } else {
      _turn(_drag.dy > 0 ? Dir.down : Dir.up);
    }
    _drag = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1A12),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _drag = Offset.zero,
        onPanUpdate: _onPanUpdate,
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: cols / rows,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CustomPaint(
                              painter: _BoardPainter(
                                snake: snake,
                                food: food,
                                cols: cols,
                                rows: rows,
                                dir: dir,
                              ),
                            ),
                          ),
                          if (!running) _overlay(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Проводи пальцем по экрану, чтобы поворачивать',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: [
          _stat('Счёт', score),
          const SizedBox(width: 24),
          _stat('Рекорд', best),
          const Spacer(),
          IconButton(
            iconSize: 32,
            color: Colors.white70,
            onPressed: gameOver ? null : (running ? _pause : _start),
            icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _overlay() {
    String title;
    String? subtitle;
    String button;
    if (gameOver) {
      title = won ? 'Победа!' : 'Игра окончена';
      subtitle = 'Счёт: $score';
      button = 'Ещё раз';
    } else if (!started) {
      title = 'Змейка';
      subtitle = 'Проведи пальцем или нажми «Играть»';
      button = 'Играть';
    } else {
      title = 'Пауза';
      button = 'Продолжить';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              textStyle:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            onPressed: _start,
            child: Text(button),
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.snake,
    required this.food,
    required this.cols,
    required this.rows,
    required this.dir,
  });

  final List<Point<int>> snake;
  final Point<int> food;
  final int cols;
  final int rows;
  final Dir dir;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;

    // Поле в клетку
    final light = Paint()..color = const Color(0xFF1C3324);
    final dark = Paint()..color = const Color(0xFF182C1F);
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < rows; y++) {
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
          (x + y).isEven ? light : dark,
        );
      }
    }

    // Еда
    final fc = Offset((food.x + 0.5) * cell, (food.y + 0.5) * cell);
    canvas.drawCircle(fc, cell * 0.38, Paint()..color = const Color(0xFFE5484D));
    canvas.drawCircle(fc + Offset(-cell * 0.12, -cell * 0.12), cell * 0.1,
        Paint()..color = Colors.white.withValues(alpha: 0.6));

    // Змейка
    for (var i = snake.length - 1; i >= 0; i--) {
      final p = snake[i];
      final t = snake.length == 1 ? 0.0 : i / (snake.length - 1);
      final color = Color.lerp(
          const Color(0xFF7EE787), const Color(0xFF2E9E4A), t)!;
      final r = Rect.fromLTWH(p.x * cell, p.y * cell, cell, cell)
          .deflate(cell * 0.06);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(cell * 0.3)),
        Paint()..color = color,
      );
    }

    // Глаза
    if (snake.isNotEmpty) {
      final h = snake.first;
      final c = Offset((h.x + 0.5) * cell, (h.y + 0.5) * cell);
      final f = cell * 0.18; // вперёд
      final s = cell * 0.2; // в стороны
      final (Offset e1, Offset e2) = switch (dir) {
        Dir.right => (c + Offset(f, -s), c + Offset(f, s)),
        Dir.left => (c + Offset(-f, -s), c + Offset(-f, s)),
        Dir.up => (c + Offset(-s, -f), c + Offset(s, -f)),
        Dir.down => (c + Offset(-s, f), c + Offset(s, f)),
      };
      final white = Paint()..color = Colors.white;
      final black = Paint()..color = Colors.black;
      for (final e in [e1, e2]) {
        canvas.drawCircle(e, cell * 0.12, white);
        canvas.drawCircle(e, cell * 0.06, black);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
