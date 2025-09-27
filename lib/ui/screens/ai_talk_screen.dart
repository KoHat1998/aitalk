import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AiTalkScreen extends StatelessWidget {
  const AiTalkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    final scaffoldBg = theme.scaffoldBackgroundColor;
    final cardColor = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final divider = theme.dividerColor.withOpacity(0.12);
    final subtle = text.bodySmall?.copyWith(color: onSurface.withOpacity(0.65));

    const devs = [
      _Dev(
        name: 'Hein Thaw Sitt',
        role: 'TharGuu',
        photo: 'assets/devs/hein.jpg',
        linkedin: 'https://www.linkedin.com/in/hein-thaw-sitt-8130822b4/',
      ),
      _Dev(
        name: 'Htet Aung Thant',
        role: 'Ko Hat',
        photo: 'assets/devs/devb.jpg',
        linkedin: 'https://www.linkedin.com/in/htet-aung-thant-378960218/',
      ),
      _Dev(
        name: 'Pai Zay Oo',
        role: 'Philip',
        photo: 'assets/devs/devc.jpg',
        linkedin: 'https://www.linkedin.com/in/paizay-oo-420a0429a/',
      ),
    ];

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('AI TALK'),
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== Bigger Logo =====
          SizedBox(
            height: 180, // increased from 120
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 0.78,
                child: Image.asset(
                  'assets/logo/ai_talk_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          const SizedBox(height: 30),
          const _SectionTitle('About', big: true),

          // ===== About text with more line spacing =====
          Text(
            'AI TALK is a next-generation communication platform created to bring people '
                'closer together through smart technology and intuitive design. Our mission is '
                'to provide a space where conversations feel natural, private, and secure, while '
                'still being powered by advanced features.\n\n'
                'With AI TALK, you can enjoy direct messaging, group chats, voice and video calls, '
                'media sharing, push notifications, and a built-in help & support system whenever you need assistance. '
                'We truly value your feedback and are committed to making AI TALK better with every update.\n\n'
                'Our focus is on speed, reliability, and simplicity — so you can spend less time navigating menus and '
                'more time staying connected with the people who matter most.\n\n'
                'Whether you are collaborating with a team, staying in touch with friends, or building a community, '
                'AI TALK is designed to support every kind of conversation. Our vision is to combine seamless user '
                'experience with trustworthy technology, making communication effortless, meaningful, and accessible '
                'to everyone.',
            style: text.bodyMedium?.copyWith(
              color: onSurface,
              height: 1.8, // increased line spacing
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 32),
          const _SectionTitle('Our Developers', big: true),

          // ===== Developer rows
          for (final d in devs)
            Card(
              color: cardColor,
              surfaceTintColor: Colors.transparent,
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _Avatar(photo: d.photo, initials: _initials(d.name)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(d.role, style: subtle),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 110),
                      child: FilledButton.icon(   // <- changed from OutlinedButton.icon
                        onPressed: () => _openUrl(d.linkedin),
                        icon: const Icon(Icons.link, color: Colors.white),
                        label: const Text('LinkedIn'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0A66C2), // LinkedIn brand blue
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),
          Divider(color: divider),
          const SizedBox(height: 8),
          Center( // Centered footer text
            child: Text(
              'AI TALK • Made by our small team with care.',
              style: subtle,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  static Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final bool big;
  const _SectionTitle(this.label, {this.big = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: big ? 20 : 16, // bigger title
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Dev {
  final String name, role, photo, linkedin;
  const _Dev({
    required this.name,
    required this.role,
    required this.photo,
    required this.linkedin,
  });
}

class _Avatar extends StatelessWidget {
  final String photo;
  final String initials;
  const _Avatar({required this.photo, required this.initials, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceVariant.withOpacity(0.24);
    final border = theme.dividerColor.withOpacity(0.15);

    final provider = photo.startsWith('http')
        ? NetworkImage(photo)
        : AssetImage(photo) as ImageProvider;

    return Container(
      width: 52, // slightly bigger avatar
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: provider,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Text(
            initials,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
