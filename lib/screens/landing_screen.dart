import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/premium_card.dart';
import '../widgets/animated_button.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -200,
            left: -200,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.2), blurRadius: 200, spreadRadius: 100),
                ],
              ),
            ),
          ).animate(onPlay: (controller) => controller.repeat(reverse: true)).move(duration: 5.seconds, begin: const Offset(0, 0), end: const Offset(50, 50)),
          
          Positioned(
            bottom: -200,
            right: -200,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C3AED).withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.2), blurRadius: 200, spreadRadius: 100),
                ],
              ),
            ),
          ).animate(onPlay: (controller) => controller.repeat(reverse: true)).move(duration: 7.seconds, begin: const Offset(0, 0), end: const Offset(-50, -50)),

          CustomScrollView(
            slivers: [
              _buildAppBar(context),
              SliverToBoxAdapter(child: _buildHeroSection(context)),
              SliverToBoxAdapter(child: _buildFeaturesSection(context)),
              SliverToBoxAdapter(child: _buildPricingSection(context)),
              SliverToBoxAdapter(child: _buildFooter(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          const Icon(Icons.security, color: Color(0xFF00E5FF), size: 28)
              .animate()
              .scale(delay: 200.ms, duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(width: 8),
          Text(
            'Vigil',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
              fontSize: 26,
            ),
          ).animate().fadeIn(delay: 300.ms).moveX(begin: -10, end: 0),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {},
          child: Text('Features', style: GoogleFonts.inter(color: Colors.white70)),
        ).animate().fadeIn(delay: 400.ms),
        TextButton(
          onPressed: () {},
          child: Text('Pricing', style: GoogleFonts.inter(color: Colors.white70)),
        ).animate().fadeIn(delay: 500.ms),
        const SizedBox(width: 16),
        SizedBox(
          width: 140,
          child: AnimatedButton(
            text: 'Login',
            onPressed: () => context.go('/login'),
          ),
        ).animate().fadeIn(delay: 600.ms).scale(curve: Curves.easeOutBack),
        const SizedBox(width: 24),
      ],
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 140, horizontal: 24),
      child: Column(
        children: [

          const SizedBox(height: 32),
          Text(
            'Predictive Compliance,\nZero Friction.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 72,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -2.0,
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 800.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
          const SizedBox(height: 24),
          Text(
            'Vigil uses advanced machine learning to proactively detect missed clock-ins,\nroster breaches, and timesheet fraud before they hit payroll.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              color: Colors.white54,
              height: 1.6,
            ),
          ).animate().fadeIn(delay: 400.ms, duration: 800.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: AnimatedButton(
                  text: 'Access Workspace',
                  onPressed: () => context.go('/login'),
                ),
              ).animate().fadeIn(delay: 600.ms).scale(curve: Curves.easeOutBack),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 26),
                  textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('View Documentation'),
              ).animate().fadeIn(delay: 700.ms).scale(curve: Curves.easeOutBack),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 24),
      child: Column(
        children: [
          Text(
            'Advanced AI Capabilities',
            style: GoogleFonts.outfit(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2, end: 0),
          const SizedBox(height: 60),
          Wrap(
            spacing: 32,
            runSpacing: 32,
            alignment: WrapAlignment.center,
            children: [
              _FeatureCard(
                icon: Icons.psychology,
                title: 'Anomaly Detection',
                description: 'Unsupervised ML identifies unusual clock-in locations and times instantly.',
                gradientColors: const [Color(0xFF00E5FF), Color(0xFF0088FF)],
                delay: 200,
              ),
              _FeatureCard(
                icon: Icons.shield,
                title: 'Fraud Classifier',
                description: 'XGBoost models score buddy-punching and spoofing risk in real-time.',
                gradientColors: const [Color(0xFF7C3AED), Color(0xFFD946EF)],
                delay: 400,
              ),
              _FeatureCard(
                icon: Icons.auto_graph,
                title: 'LLM Reporting',
                description: 'Generative AI transforms complex exceptions into plain-English manager briefings.',
                gradientColors: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                delay: 600,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPricingSection(BuildContext context) {
    // Simplified for prototype, focusing on premium look
    return const SizedBox(height: 100);
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Text(
          '© 2026 Vigil AI Engine. All rights reserved.',
          style: GoogleFonts.inter(color: Colors.white24),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradientColors;
  final int delay;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradientColors,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Container(
        width: 320,
        height: 280,
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors.map((c) => c.withOpacity(0.2)).toList(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: gradientColors[0].withOpacity(0.5)),
              ),
              child: Icon(icon, color: gradientColors[0], size: 36),
            ),
            const Spacer(),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: GoogleFonts.inter(color: Colors.white60, height: 1.5),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: delay.ms, duration: 800.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad);
  }
}
