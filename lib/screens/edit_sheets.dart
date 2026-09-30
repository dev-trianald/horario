import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/schedule.dart';
import '../models/task.dart';

class TaskDraft {
  const TaskDraft({
    required this.day,
    required this.subject,
    required this.message,
    required this.weekStart,
    required this.isExam,
  });

  final String day;
  final String subject;
  final String message;
  final DateTime weekStart;
  final bool isExam;
}

class ReminderDraft {
  const ReminderDraft({required this.subject, required this.message});

  final String subject;
  final String message;
}

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({
    super.key,
    required this.day,
    required this.subject,
    this.task,
  });

  final String day;
  final String subject;
  final TaskItem? task;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _messageController;
  late String _day;
  late String _subject;
  late DateTime _weekStart;
  late bool _isExam;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: widget.task?.message ?? '');
    _day = widget.task?.day ?? widget.day;
    _subject = widget.task?.subject ?? widget.subject;
    _weekStart = mondayOf(widget.task?.weekStart ?? DateTime.now());
    _isExam = widget.task?.isExam ?? false;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _selectWeek() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'Elige cualquier día de la semana',
    );
    if (selected != null) setState(() => _weekStart = mondayOf(selected));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      TaskDraft(
        day: _day,
        subject: _subject,
        message: _messageController.text.trim().isEmpty
            ? 'Examen'
            : _messageController.text.trim(),
        weekStart: _weekStart,
        isExam: _isExam,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.task == null ? 'Nueva tarea o examen' : 'Editar apunte',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _day,
                          decoration: const InputDecoration(labelText: 'Día'),
                          items: weekdays.map((day) => DropdownMenuItem(value: day, child: Text(day))).toList(),
                          onChanged: (value) => setState(() => _day = value!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _subject,
                          decoration: const InputDecoration(labelText: 'Asignatura'),
                          items: subjects.map((subject) => DropdownMenuItem(value: subject, child: Text(subject))).toList(),
                          onChanged: (value) => setState(() => _subject = value!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _messageController,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Detalles',
                      hintText: 'Describe la tarea o el examen',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) && !_isExam
                            ? 'Escribe los detalles o marca que es un examen.'
                            : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Marcar como examen'),
                    value: _isExam,
                    onChanged: (value) => setState(() => _isExam = value),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _selectWeek,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('Semana del ${DateFormat('dd/MM/yyyy').format(_weekStart)}'),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class ReminderEditorSheet extends StatefulWidget {
  const ReminderEditorSheet({super.key, this.reminder});

  final ReminderItem? reminder;

  @override
  State<ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends State<ReminderEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _messageController;
  late String? _subject;

  @override
  void initState() {
    super.initState();
    _subject = widget.reminder?.subject;
    _messageController = TextEditingController(text: widget.reminder?.message ?? '');
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ReminderDraft(subject: _subject!, message: _messageController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.reminder == null ? 'Nuevo recordatorio' : 'Editar recordatorio',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _subject,
                    decoration: const InputDecoration(labelText: 'Asignatura'),
                    items: subjects.map((subject) => DropdownMenuItem(value: subject, child: Text(subject))).toList(),
                    validator: (value) => value == null ? 'Selecciona una asignatura.' : null,
                    onChanged: (value) => setState(() => _subject = value),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _messageController,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Contenido',
                      hintText: 'Temas, apuntes o información importante',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Escribe el contenido del recordatorio.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _createAccount = false;
  bool _submitting = false;
  String? _feedback;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    try {
      if (_createAccount) {
        final response = await widget.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (response.session == null && mounted) {
          setState(() => _feedback = 'Cuenta creada. Revisa tu correo para confirmar la dirección.');
        } else if (mounted) {
          Navigator.pop(context);
        }
      } else {
        await widget.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _feedback = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _createAccount ? 'Crear cuenta' : 'Iniciar sesión',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Correo electrónico'),
                    validator: (value) => value == null || !value.contains('@')
                        ? 'Introduce un correo válido.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (value) => value == null || value.length < 6
                        ? 'La contraseña debe tener al menos 6 caracteres.'
                        : null,
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 12),
                    Text(_feedback!, style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_createAccount ? 'Crear cuenta' : 'Iniciar sesión'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() {
                                _createAccount = !_createAccount;
                                _feedback = null;
                              }),
                      child: Text(_createAccount ? 'Ya tengo una cuenta' : 'Crear una cuenta nueva'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}