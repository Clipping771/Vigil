import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/agent_service.dart';

class AgentFAB extends ConsumerStatefulWidget {
  const AgentFAB({super.key});

  @override
  ConsumerState<AgentFAB> createState() => _AgentFABState();
}

class _AgentFABState extends ConsumerState<AgentFAB> {
  bool _isExpanded = false;
  bool _isLoading = false;
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded && _messages.isEmpty) {
        _messages.add({'sender': 'agent', 'text': 'Hello! I am Vigil AI. How can I help you? (e.g. "turn on light mode")'});
      }
    });
  }

  Future<void> _submitCommand() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _isLoading = true;
    });
    _controller.clear();

    final response = await ref.read(agentServiceProvider).executeCommand(text, context);

    setState(() {
      _isLoading = false;
      _messages.add({'sender': 'agent', 'text': response});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isExpanded) {
      return FloatingActionButton(
        onPressed: _toggleExpanded,
        backgroundColor: const Color(0xFF7C3AED),
        child: const Icon(Icons.auto_awesome, color: Colors.white),
      ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms);
    }

    return Container(
      width: 350,
      height: 450,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.2), blurRadius: 30, spreadRadius: 5),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF7C3AED).withOpacity(0.2), Colors.transparent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED), size: 20),
                    const SizedBox(width: 8),
                    Text('Vigil Assistant', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _toggleExpanded,
                )
              ],
            ),
          ),
          
          // Chat Log
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isAgent = msg['sender'] == 'agent';
                return Align(
                  alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isAgent ? const Color(0xFF7C3AED).withOpacity(0.15) : Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isAgent ? const Color(0xFF7C3AED).withOpacity(0.3) : Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                    ),
                    child: Text(msg['text']!, style: const TextStyle(fontSize: 14)),
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
              },
            ),
          ),
          
          // Loading Indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C3AED))),
            ),
          
          // Input
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _submitCommand(),
                    decoration: InputDecoration(
                      hintText: 'Type a command...',
                      hintStyle: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _submitCommand,
                  ),
                )
              ],
            ),
          )
        ],
      ),
    ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms);
  }
}
