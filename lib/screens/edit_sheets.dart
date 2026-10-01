import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/schedule.dart';
import '../models/schedule_class.dart';
import '../models/task.dart';

class ClassDraft {
  const ClassDraft(this.name, {this.scheduleTemplateId, this.accessCode});

  final String name;
  final String? scheduleTemplateId;
  final String? accessCode;
}

class ClassEditorSheet extends StatefulWidget {
  const ClassEditorSheet({
    super.key,
    this.initialName,
    this.scheduleTemplates = const [],
  });

  final String? initialName;
  final List<ScheduleClass> scheduleTemplates;

  @override
  State<ClassEditorSheet> createState() => _ClassEditorSheetState();
}

class _ClassEditorSheetState extends State<ClassEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  String? _scheduleTemplateId;

  bool get _isEditing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ClassDraft(
        _nameController.text.trim(),
        scheduleTemplateId: _scheduleTemplateId,
        accessCode: _codeController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  22, 12, 22, 24 + MediaQuery.viewInsetsOf(context).bottom),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isEditing ? 'Editar nombre de clase' : 'Crear clase',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la clase',
                        hintText: 'Por ejemplo, 2º DAM',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Escribe un nombre.'
                              : null,
                    ),
                    if (!_isEditing) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 12,
                        decoration: const InputDecoration(
                          labelText: 'Código de acceso',
                          hintText: 'Por ejemplo, DAM2026',
                          helperText: 'Elige de 6 a 12 letras o números.',
                        ),
                        validator: (value) => value == null ||
                                !RegExp(r'^[A-Za-z0-9]{6,12}$')
                                    .hasMatch(value.trim())
                            ? 'Usa entre 6 y 12 letras o números.'
                            : null,
                      ),
                    ],
                    if (!_isEditing && widget.scheduleTemplates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _scheduleTemplateId ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Horario',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Crear desde cero'),
                          ),
                          for (final schedule in widget.scheduleTemplates)
                            DropdownMenuItem(
                              value: schedule.id,
                              child: Text(schedule.name),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _scheduleTemplateId =
                              value?.isEmpty == true ? null : value,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon:
                            Icon(_isEditing ? Icons.save_outlined : Icons.add),
                        label:
                            Text(_isEditing ? 'Guardar nombre' : 'Crear clase'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class AccessCodeSheet extends StatefulWidget {
  const AccessCodeSheet({super.key});

  @override
  State<AccessCodeSheet> createState() => _AccessCodeSheetState();
}

class _AccessCodeSheetState extends State<AccessCodeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _codeController.text.trim());
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              22, 12, 22, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Buscar una clase',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _codeController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: 'Código de acceso',
                  ),
                  validator: (value) => value == null ||
                          !RegExp(r'^[A-Za-z0-9]{6,12}$').hasMatch(value.trim())
                      ? 'Escribe un código válido de 6 a 12 caracteres.'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar clase'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class SubjectDraft {
  const SubjectDraft({
    required this.name,
    required this.teacher,
    required this.color,
  });

  final String name;
  final String teacher;
  final Color color;
}

class SubjectEditorSheet extends StatefulWidget {
  const SubjectEditorSheet({super.key});

  @override
  State<SubjectEditorSheet> createState() => _SubjectEditorSheetState();
}

class _SubjectEditorSheetState extends State<SubjectEditorSheet> {
  static const _colors = [
    Color(0xFF2787A0),
    Color(0xFF2D8A62),
    Color(0xFFAD623C),
    Color(0xFF7059A5),
    Color(0xFFB28A23),
    Color(0xFF3C687D),
    Color(0xFFAA4961),
    Color(0xFF59666A),
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _teacherController = TextEditingController();
  Color _color = _colors.first;

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      SubjectDraft(
        name: _nameController.text.trim(),
        teacher: _teacherController.text.trim(),
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Crear asignatura',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _nameController,
                    autofocus: true,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Escribe un nombre.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _teacherController,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'Profesor'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Escribe el nombre del profesor.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text('Color', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final color in _colors)
                        InkWell(
                          onTap: () => setState(() => _color = color),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == color
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir asignatura'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

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
    this.availableSubjects = const [],
    this.task,
  });

  final String day;
  final String subject;
  final List<ClassSubject> availableSubjects;
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

  List<String> get _subjectOptions {
    final options = widget.availableSubjects.isEmpty
        ? subjects
        : widget.availableSubjects.map((subject) => subject.name).toList();
    return options.contains(_subject) ? options : [...options, _subject];
  }

  @override
  void initState() {
    super.initState();
    _messageController =
        TextEditingController(text: widget.task?.message ?? '');
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
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.task == null
                        ? 'Nueva tarea o examen'
                        : 'Editar apunte',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _day,
                          decoration: const InputDecoration(labelText: 'Día'),
                          items: weekdays
                              .map((day) => DropdownMenuItem(
                                  value: day, child: Text(day)))
                              .toList(),
                          onChanged: (value) => setState(() => _day = value!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _subject,
                          decoration:
                              const InputDecoration(labelText: 'Asignatura'),
                          items: _subjectOptions
                              .map((subject) => DropdownMenuItem(
                                  value: subject, child: Text(subject)))
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _subject = value!),
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
                    label: Text(
                        'Semana del ${DateFormat('dd/MM/yyyy').format(_weekStart)}'),
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
  const ReminderEditorSheet({
    super.key,
    this.reminder,
    this.availableSubjects = const [],
  });

  final ReminderItem? reminder;
  final List<String> availableSubjects;

  @override
  State<ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends State<ReminderEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _messageController;
  late String? _subject;

  List<String> get _subjectOptions {
    final options =
        widget.availableSubjects.isEmpty ? subjects : widget.availableSubjects;
    final selected = _subject;
    return selected == null || options.contains(selected)
        ? options
        : [...options, selected];
  }

  @override
  void initState() {
    super.initState();
    _subject = widget.reminder?.subject;
    _messageController =
        TextEditingController(text: widget.reminder?.message ?? '');
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
      ReminderDraft(
          subject: _subject!, message: _messageController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.reminder == null
                        ? 'Nuevo recordatorio'
                        : 'Editar recordatorio',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _subject,
                    decoration: const InputDecoration(labelText: 'Asignatura'),
                    items: _subjectOptions
                        .map((subject) => DropdownMenuItem(
                            value: subject, child: Text(subject)))
                        .toList(),
                    validator: (value) =>
                        value == null ? 'Selecciona una asignatura.' : null,
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
  const AuthSheet({super.key, required this.auth});

  final FirebaseAuth auth;

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
        await widget.auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await widget.auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _feedback = _authErrorMessage(error));
    } catch (_) {
      if (mounted) {
        setState(() => _feedback =
            'No se pudo conectar con Firebase. Comprueba la conexión e inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    try {
      final provider = GoogleAuthProvider()
        ..addScope('https://www.googleapis.com/auth/spreadsheets');
      if (kIsWeb) {
        await widget.auth.signInWithPopup(provider);
      } else {
        final googleSignIn = GoogleSignIn(
          scopes: [
            'email',
            'https://www.googleapis.com/auth/spreadsheets',
          ],
        );
        final account = await googleSignIn.signIn();
        if (account == null) return;
        final authentication = await account.authentication;
        final idToken = authentication.idToken;
        if (idToken == null) {
          throw StateError('Google no devolvió un token de acceso.');
        }
        await widget.auth.signInWithCredential(
          GoogleAuthProvider.credential(
            idToken: idToken,
            accessToken: authentication.accessToken,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _feedback = _authErrorMessage(error));
    } catch (error) {
      if (mounted) {
        setState(() => _feedback =
            'No se pudo iniciar sesión con Google. Comprueba la configuración del proveedor e inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 26),
                      label: const Text('Continuar con Google'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(child: Text('o con correo electrónico')),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration:
                        const InputDecoration(labelText: 'Correo electrónico'),
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
                    Text(_feedback!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_createAccount
                              ? 'Crear cuenta'
                              : 'Iniciar sesión'),
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
                      child: Text(_createAccount
                          ? 'Ya tengo una cuenta'
                          : 'Crear una cuenta nueva'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

String _authErrorMessage(FirebaseAuthException error) => switch (error.code) {
      'email-already-in-use' => 'Ya existe una cuenta con ese correo.',
      'invalid-email' => 'El correo no tiene un formato válido.',
      'weak-password' => 'La contraseña es demasiado débil.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'El correo o la contraseña no son correctos.',
      'user-disabled' => 'Esta cuenta está desactivada.',
      'too-many-requests' =>
        'Demasiados intentos. Espera un momento e inténtalo de nuevo.',
      'network-request-failed' =>
        'No hay conexión con Firebase. Comprueba la configuración y tu conexión a Internet.',
      _ => error.message ?? 'No se pudo iniciar sesión.',
    };
