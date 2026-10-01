import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/schedule.dart';
import '../models/schedule_class.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import 'edit_sheets.dart';

const _desktopTimeColumnWidth = 104.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.auth,
    required this.firestore,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TaskService _service = TaskService(widget.firestore, widget.auth);
  late User? _user = widget.auth.currentUser;
  StreamSubscription<User?>? _authSubscription;
  List<ScheduleClass> _classes = [];
  List<TaskItem> _tasks = [];
  List<ReminderItem> _reminders = [];
  List<ClassMember> _classMembers = [];
  List<TaskItem> _memberTasks = [];
  List<ReminderItem> _memberReminders = [];
  bool _loadingData = false;
  bool _loadingClassMembers = false;
  bool _loadingMemberItems = false;
  bool _showTaskHistory = false;
  bool _showReminderHistory = false;
  bool _showClassMembers = false;
  int _tab = 0;
  int _selectedDay = (DateTime.now().weekday - 1).clamp(0, 4).toInt();
  String? _selectedClassId;
  String? _selectedMemberId;
  bool _editingSchedule = false;

  ScheduleClass? get _selectedClass {
    final id = _selectedClassId;
    if (id == null) return null;
    for (final classItem in _classes) {
      if (classItem.id == id) return classItem;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.auth.authStateChanges().listen((user) {
      if (!mounted) return;
      setState(() => _user = user);
      if (_user == null) {
        setState(() {
          _classes = [];
          _selectedClassId = null;
          _tasks = [];
          _reminders = [];
        });
      } else {
        unawaited(_loadData());
      }
    });
    if (_user != null) unawaited(_loadData());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted || _user == null) return;
    setState(() => _loadingData = true);
    try {
      final results = await Future.wait([
        _service.loadClasses(),
        _service.loadTasks(),
        _service.loadReminders(),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = results[0] as List<ScheduleClass>;
        _tasks = results[1] as List<TaskItem>;
        _reminders = results[2] as List<ReminderItem>;
        if (_selectedClassId != null &&
            !_classes.any((item) => item.id == _selectedClassId)) {
          _selectedClassId = null;
        }
      });
    } catch (error) {
      _showMessage('No se pudieron cargar tus datos: $error');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _perform(Future<void> Function() operation) async {
    try {
      await operation();
      await _loadData();
      if (mounted) _showMessage('Cambios guardados.');
    } catch (error) {
      _showMessage('No se pudo guardar el cambio: $error');
    }
  }

  Future<bool> _ensureSignedIn(String message) async {
    if (_user != null) return true;
    _showMessage(message);
    await _showAccount();
    return _user != null;
  }

  Future<void> _createClass() async {
    if (!await _ensureSignedIn('Inicia sesión para crear tus clases.')) return;
    if (!mounted) return;
    final draft = await showModalBottomSheet<ClassDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ClassEditorSheet(
        scheduleTemplates:
            _classes.where((classItem) => classItem.hasSchedule).toList(),
      ),
    );
    if (!mounted || draft == null) return;
    try {
      final scheduleTemplate = _classes
          .where((classItem) => classItem.id == draft.scheduleTemplateId)
          .firstOrNull;
      final id = await _service.createClass(
        draft.name,
        draft.accessCode!,
        scheduleTemplate: scheduleTemplate,
      );
      if (!mounted) return;
      setState(() {
        _selectedClassId = id;
        _showClassMembers = false;
        _tab = 0;
      });
      await _loadData();
    } catch (error) {
      _showMessage('No se pudo crear la clase: $error');
    }
  }

  Future<void> _joinClass() async {
    if (!await _ensureSignedIn('Inicia sesión para buscar una clase.')) return;
    if (!mounted) return;
    final accessCode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const AccessCodeSheet(),
    );
    if (!mounted || accessCode == null) return;
    try {
      final id = await _service.joinClass(accessCode);
      if (!mounted) return;
      setState(() {
        _selectedClassId = id;
        _showClassMembers = false;
        _tab = 0;
      });
      await _loadData();
    } catch (error) {
      _showMessage('No se pudo acceder a la clase: $error');
    }
  }

  Future<void> _editClassName() async {
    final classItem = _selectedClass;
    if (classItem == null) return;
    if (!await _ensureSignedIn('Inicia sesión para editar la clase.')) return;
    if (!mounted) return;
    final draft = await showModalBottomSheet<ClassDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ClassEditorSheet(initialName: classItem.name),
    );
    if (!mounted || draft == null) return;
    await _perform(() => _service.renameClass(classItem.id, draft.name));
  }

  Future<void> _createSchedule() async {
    final classItem = _selectedClass;
    if (classItem == null) return;
    if (!await _ensureSignedIn('Inicia sesión para crear el horario.')) return;
    await _perform(() => _service.createSchedule(classItem.id));
  }

  Future<void> _createSubject() async {
    final classItem = _selectedClass;
    if (classItem == null || classItem.isComplete) return;
    if (!await _ensureSignedIn('Inicia sesión para crear asignaturas.')) return;
    if (!mounted) return;
    final draft = await showModalBottomSheet<SubjectDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const SubjectEditorSheet(),
    );
    if (!mounted || draft == null) return;
    final color = _colorHex(draft.color);
    await _perform(() => _service.saveSubject(
          classId: classItem.id,
          name: draft.name,
          teacher: draft.teacher,
          color: color,
        ));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAccount() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _user == null
          ? AuthSheet(auth: widget.auth)
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tu cuenta',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(_user?.email ?? ''),
                    const SizedBox(height: 20),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await widget.auth.signOut();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _editTask({
    required String day,
    required String subject,
    TaskItem? task,
  }) async {
    if (_user == null) {
      _showMessage('Inicia sesión para añadir tareas y exámenes.');
      await _showAccount();
      return;
    }
    final classItem = _selectedClass;
    if (classItem == null || classItem.subjects.isEmpty) {
      _showMessage('Crea al menos una asignatura antes de añadir tareas.');
      return;
    }
    final draft = await showModalBottomSheet<TaskDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TaskEditorSheet(
        day: day,
        subject: subject,
        availableSubjects: classItem.subjects,
        task: task,
      ),
    );
    if (!mounted || draft == null) return;
    final selectedSubject = classItem.subjects
        .where((item) => item.name == draft.subject)
        .firstOrNull;
    await _perform(() => _service.saveTask(
          id: task?.id,
          day: draft.day,
          subject: draft.subject,
          message: draft.message,
          color: selectedSubject?.color ?? '#2787A0',
          weekStart: draft.weekStart,
          isExam: draft.isExam,
          scheduleId: classItem.id,
        ));
  }

  Future<void> _editReminder({ReminderItem? reminder}) async {
    if (_user == null) {
      _showMessage('Inicia sesión para guardar recordatorios.');
      await _showAccount();
      return;
    }
    final draft = await showModalBottomSheet<ReminderDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ReminderEditorSheet(
        reminder: reminder,
        availableSubjects:
            _selectedClass?.subjects.map((subject) => subject.name).toList() ??
                const [],
      ),
    );
    if (!mounted || draft == null) return;
    await _perform(() => _service.saveReminder(
          id: reminder?.id,
          subject: draft.subject,
          message: draft.message,
          scheduleId: _selectedClass?.id,
        ));
  }

  Future<void> _loadClassMembers() async {
    final classItem = _selectedClass;
    if (classItem == null) return;
    setState(() {
      _loadingClassMembers = true;
      _classMembers = [];
      _selectedMemberId = null;
      _memberTasks = [];
      _memberReminders = [];
    });
    try {
      if (classItem.accessCode.isEmpty) return;
      final members = await _service.loadClassMembers(classItem.id);
      if (mounted) setState(() => _classMembers = members);
    } catch (error) {
      _showMessage('No se pudieron cargar los usuarios de la clase: $error');
    } finally {
      if (mounted) setState(() => _loadingClassMembers = false);
    }
  }

  Future<void> _openClassMembers() async {
    setState(() {
      _showClassMembers = true;
      _tab = 3;
    });
    await _loadClassMembers();
  }

  Future<void> _selectClassMember(ClassMember member) async {
    final classItem = _selectedClass;
    if (classItem == null) return;
    setState(() {
      _selectedMemberId = member.id;
      _loadingMemberItems = true;
      _memberTasks = [];
      _memberReminders = [];
    });
    try {
      final results = await Future.wait([
        _service.loadMemberTasks(classId: classItem.id, memberId: member.id),
        _service.loadMemberReminders(
            classId: classItem.id, memberId: member.id),
      ]);
      if (!mounted) return;
      setState(() {
        _memberTasks = results[0] as List<TaskItem>;
        _memberReminders = results[1] as List<ReminderItem>;
      });
    } catch (error) {
      _showMessage('No se pudieron consultar sus apuntes: $error');
    } finally {
      if (mounted) setState(() => _loadingMemberItems = false);
    }
  }

  Future<bool> _confirmDelete(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text('Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteTask(TaskItem task) async {
    if (!await _confirmDelete('¿Eliminar esta tarea?')) return;
    await _perform(() => _service.deleteTask(task.id));
  }

  Future<void> _deleteClass(ScheduleClass classItem) async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('¿Salir de "${classItem.name}"?'),
            content: const Text(
                'La clase seguirá disponible para sus demás miembros.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldLeave) {
      return;
    }
    await _perform(() => _service.deleteClass(classItem.id));
  }

  Future<void> _deleteReminder(ReminderItem reminder) async {
    if (!await _confirmDelete('¿Eliminar este recordatorio?')) return;
    await _perform(() => _service.deleteReminder(reminder.id));
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Horario',
      'Tareas y exámenes',
      'Recordatorios',
      'Usuarios de la clase',
    ];
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    final activeClass = _selectedClass;
    return Scaffold(
      appBar: AppBar(
        leading: activeClass == null
            ? null
            : IconButton(
                tooltip: _showClassMembers
                    ? 'Volver a la clase'
                    : 'Volver a mis clases',
                onPressed: () => setState(() {
                  if (_showClassMembers) {
                    _showClassMembers = false;
                    _selectedMemberId = null;
                    _tab = 0;
                  } else {
                    _selectedClassId = null;
                    _editingSchedule = false;
                    _tab = 0;
                  }
                }),
                icon: const Icon(Icons.arrow_back),
              ),
        title: Row(
          children: [
            const _TaskDamLogo(size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeClass?.name ?? 'TaskDAM',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    activeClass == null
                        ? 'Mis clases'
                        : _showClassMembers || _tab == 3
                            ? 'Usuarios de la clase'
                            : !activeClass.hasSchedule
                                ? 'Configura tu horario'
                                : isDesktop
                                    ? 'Horario · Tareas · Recordatorios'
                                    : titles[_tab],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (activeClass != null && isDesktop)
            IconButton(
              tooltip: 'Usuarios de la clase',
              onPressed: _openClassMembers,
              icon: const Icon(Icons.groups_outlined),
            ),
          if (activeClass != null)
            IconButton(
              tooltip: 'Editar nombre de la clase',
              onPressed: _editClassName,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (_loadingData)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: _user == null ? 'Iniciar sesión' : 'Cuenta',
            onPressed: _showAccount,
            icon: Icon(
                _user == null ? Icons.person_outline : Icons.account_circle),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: activeClass == null
          ? _buildClassHome()
          : isDesktop
              ? _showClassMembers
                  ? _buildClassMembers()
                  : _buildDesktopDashboard()
              : IndexedStack(
                  index: _tab,
                  children: [
                    _buildSchedule(),
                    _buildTasks(),
                    _buildReminders(),
                    _buildClassMembers(),
                  ],
                ),
      floatingActionButton: activeClass != null &&
              activeClass.hasSchedule &&
              activeClass.subjects.isNotEmpty &&
              !isDesktop &&
              _tab == 1 &&
              _user != null
          ? FloatingActionButton.extended(
              onPressed: () => _editTask(
                day: weekdays[_selectedDay],
                subject: activeClass.subjects.first.name,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Añadir tarea'),
            )
          : activeClass != null &&
                  activeClass.hasSchedule &&
                  !isDesktop &&
                  _tab == 2 &&
                  _user != null
              ? FloatingActionButton.extended(
                  onPressed: () => _editReminder(),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir recordatorio'),
                )
              : null,
      bottomNavigationBar: activeClass == null || isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) {
                setState(() {
                  _tab = index;
                  _showClassMembers = index == 3;
                });
                if (index == 3) unawaited(_loadClassMembers());
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.view_week_outlined), label: 'Horario'),
                NavigationDestination(
                    icon: Icon(Icons.checklist), label: 'Tareas'),
                NavigationDestination(
                    icon: Icon(Icons.bookmark_border), label: 'Recordatorios'),
                NavigationDestination(
                    icon: Icon(Icons.groups_outlined), label: 'Usuarios'),
              ],
            ),
    );
  }

  Widget _buildClassMembers() {
    final classItem = _selectedClass;
    final member =
        _classMembers.where((item) => item.id == _selectedMemberId).firstOrNull;
    if (_loadingClassMembers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (classItem?.accessCode.isEmpty == true) {
      return const _EmptyState(
        icon: Icons.groups_outlined,
        message:
            'Esta clase es privada y todavía no tiene una lista de usuarios.',
      );
    }
    if (member != null) {
      return _buildMemberNotes(member);
    }
    if (_classMembers.isEmpty) {
      return const _EmptyState(
        icon: Icons.groups_outlined,
        message: 'Todavía no hay usuarios en esta clase.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Text('Usuarios de la clase',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final classMember in _classMembers) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(classMember.name),
              subtitle: Text(classMember.id == _user?.uid
                  ? 'Tú'
                  : 'Consultar tareas y recordatorios'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectClassMember(classMember),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildMemberNotes(ClassMember member) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _selectedMemberId = null;
                _memberTasks = [];
                _memberReminders = [];
              }),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Usuarios de la clase'),
            ),
          ),
          Text(member.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          if (_loadingMemberItems)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text('Tareas y exámenes',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_memberTasks.isEmpty)
              const Text('No ha compartido tareas para esta clase.')
            else
              for (final task in _memberTasks)
                Card(
                  child: ListTile(
                    leading: Icon(task.isExam
                        ? Icons.fact_check_outlined
                        : Icons.checklist),
                    title: Text(task.subject),
                    subtitle: Text('${task.day} · ${task.message}'),
                    trailing: task.completed
                        ? const Icon(Icons.done_all, size: 18)
                        : null,
                  ),
                ),
            const SizedBox(height: 20),
            Text('Recordatorios',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_memberReminders.isEmpty)
              const Text('No ha compartido recordatorios para esta clase.')
            else
              for (final reminder in _memberReminders)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: Text(reminder.subject),
                    subtitle: Text(reminder.message),
                    trailing: reminder.completed
                        ? const Icon(Icons.done_all, size: 18)
                        : null,
                  ),
                ),
          ],
        ],
      );

  Widget _buildClassHome() => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
            children: [
              Text('Mis clases',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 6),
              Text(
                _user == null
                    ? 'Inicia sesión con Google o correo para crear tus clases y sincronizar tus horarios.'
                    : 'Crea una clase y configura su horario, asignaturas y apuntes.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_user == null)
                      FilledButton.icon(
                        onPressed: _showAccount,
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar sesión'),
                      )
                    else ...[
                      FilledButton.icon(
                        onPressed: _createClass,
                        icon: const Icon(Icons.add),
                        label: const Text('Crear clase'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _joinClass,
                        icon: const Icon(Icons.search),
                        label: const Text('Buscar una clase'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_classes.isEmpty)
                _EmptyState(
                  icon: Icons.class_outlined,
                  message: _user == null
                      ? 'Inicia sesión para crear y guardar tus clases.'
                      : 'Aún no has creado ninguna clase.',
                )
              else
                for (final classItem in _classes) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      onTap: () => setState(() {
                        _selectedClassId = classItem.id;
                        _editingSchedule = false;
                        _tab = 0;
                      }),
                      leading: const _TaskDamLogo(size: 42),
                      title: Text(classItem.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(classItem.accessCode.isEmpty
                          ? classItem.hasSchedule
                              ? '${classItem.subjects.length} asignaturas'
                              : 'Horario sin crear'
                          : '${classItem.hasSchedule ? '${classItem.subjects.length} asignaturas' : 'Horario sin crear'} · Código ${classItem.accessCode}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Salir de la clase',
                            onPressed: () => _deleteClass(classItem),
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      );

  Widget _buildScheduleSetup() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month_outlined,
                  size: 42, color: Color(0xFF46C4B2)),
              const SizedBox(height: 14),
              Text('Aún no hay horario',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Crea un horario semanal para esta clase.'),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _createSchedule,
                icon: const Icon(Icons.add),
                label: const Text('Crear horario'),
              ),
            ],
          ),
        ),
      );

  Widget _buildDesktopDashboard() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
                flex: 48, child: _DesktopPanel(child: _buildWeeklySchedule())),
            const SizedBox(width: 12),
            Expanded(
                flex: 26,
                child: _DesktopPanel(child: _buildTasks(desktop: true))),
            const SizedBox(width: 12),
            Expanded(
                flex: 26,
                child: _DesktopPanel(child: _buildReminders(desktop: true))),
          ],
        ),
      );

  Widget _buildWeeklySchedule() {
    final classItem = _selectedClass;
    if (classItem == null) return const SizedBox.shrink();
    if (!classItem.hasSchedule) return _buildScheduleSetup();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: _buildScheduleToolbar(classItem),
        ),
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: _desktopTimeColumnWidth),
                  for (final day in weekdays)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF344246),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(day,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Column(
                  children: [
                    for (var row = 0; row < 7; row++)
                      Expanded(
                        child: row == 3
                            ? const _WeeklyBreakRow()
                            : Row(
                                children: [
                                  SizedBox(
                                    width: _desktopTimeColumnWidth,
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2D393C),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          classTimes[row < 3 ? row : row - 1],
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (final day in weekdays)
                                    Expanded(
                                      child: _buildDesktopScheduleCell(
                                        classItem,
                                        day,
                                        row < 3 ? row : row - 1,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleToolbar(ScheduleClass classItem) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScheduleHeading(name: classItem.name),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (!classItem.isComplete)
                FilledButton.tonalIcon(
                  onPressed: _createSubject,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Crear asignatura'),
                ),
              OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _editingSchedule = !_editingSchedule),
                icon: Icon(_editingSchedule
                    ? Icons.check
                    : Icons.edit_calendar_outlined),
                label: Text(
                    _editingSchedule ? 'Terminar edición' : 'Editar horario'),
              ),
            ],
          ),
        ],
      );

  Widget _buildDesktopScheduleCell(
    ScheduleClass classItem,
    String day,
    int period,
  ) {
    final subject = classItem.subjectById(classItem.cells['${day}_$period']);
    if (subject == null) {
      return _EmptyScheduleCell(
        key: ValueKey('schedule-cell-$day-$period'),
        onTap: () => _assignScheduleCell(day, period),
      );
    }
    return _WeeklyClassCell(
      subject: subject,
      onTap: () => _tapScheduleCell(day, period, subject),
      editing: _editingSchedule,
    );
  }

  Widget _buildSchedule() {
    final classItem = _selectedClass;
    if (classItem == null) return const SizedBox.shrink();
    if (!classItem.hasSchedule) return _buildScheduleSetup();
    final day = weekdays[_selectedDay];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _buildScheduleToolbar(classItem),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < weekdays.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(weekdays[index]),
                  selected: _selectedDay == index,
                  onSelected: (_) => setState(() => _selectedDay = index),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (var period = 0; period < 6; period++) ...[
          if (period == 3) ...[
            const SizedBox(height: 8),
            const _BreakRow(),
            const SizedBox(height: 8),
          ],
          _buildMobileScheduleCell(classItem, day, period),
          if (period < 5) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildMobileScheduleCell(
    ScheduleClass classItem,
    String day,
    int period,
  ) {
    final subject = classItem.subjectById(classItem.cells['${day}_$period']);
    if (subject == null) {
      return _EmptyScheduleRow(
        key: ValueKey('schedule-cell-$day-$period'),
        time: classTimes[period],
        onTap: () => _assignScheduleCell(day, period),
      );
    }
    return _ClassRow(
      time: classTimes[period],
      subject: subject,
      onTap: () => _tapScheduleCell(day, period, subject),
      editing: _editingSchedule,
    );
  }

  Future<void> _assignScheduleCell(String day, int period) async {
    final classItem = _selectedClass;
    if (classItem == null) return;
    if (classItem.subjects.isEmpty) {
      _showMessage(
          'No hay asignaturas. Crea una antes de rellenar el horario.');
      return;
    }
    final selected = await showModalBottomSheet<ClassSubject>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
              child: Text('Elige asignatura',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final subject in classItem.subjects)
              ListTile(
                leading:
                    CircleAvatar(backgroundColor: _parseColor(subject.color)),
                title: Text(subject.name),
                subtitle: Text(subject.teacher),
                onTap: () => Navigator.pop(context, subject),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await _perform(() => _service.setScheduleCell(
          classId: classItem.id,
          day: day,
          period: period,
          subjectId: selected.id,
        ));
  }

  void _tapScheduleCell(String day, int period, ClassSubject subject) {
    if (_editingSchedule) {
      _editScheduleCell(day, period, subject);
    } else {
      _editTask(day: day, subject: subject.name);
    }
  }

  Future<void> _editScheduleCell(
    String day,
    int period,
    ClassSubject subject,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Mover a otra hora'),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Cambiar asignatura'),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Vaciar casilla'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'change') {
      await _assignScheduleCell(day, period);
    } else if (action == 'delete') {
      final classItem = _selectedClass;
      if (classItem != null) {
        await _perform(() => _service.setScheduleCell(
              classId: classItem.id,
              day: day,
              period: period,
              subjectId: null,
            ));
      }
    } else if (action == 'move') {
      await _moveScheduleCell(day, period, subject);
    }
  }

  Future<void> _moveScheduleCell(
    String fromDay,
    int fromPeriod,
    ClassSubject subject,
  ) async {
    final classItem = _selectedClass;
    if (classItem == null) return;
    final destinationSlots = [
      for (final day in weekdays)
        for (var period = 0; period < 6; period++)
          if (!(day == fromDay && period == fromPeriod)) '${day}_$period',
    ];
    var selectedSlot = destinationSlots.first;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mover asignatura'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Si eliges una franja ocupada, las asignaturas intercambiarán su sitio.'),
              const SizedBox(height: 12),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedSlot,
                items: [
                  for (final slot in destinationSlots)
                    DropdownMenuItem(
                      value: slot,
                      child: Text(_slotLabel(classItem, slot)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => selectedSlot = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selectedSlot),
              child: const Text('Mover'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || destination == null) return;
    final separator = destination.lastIndexOf('_');
    await _perform(() => _service.moveScheduleCell(
          classId: classItem.id,
          fromDay: fromDay,
          fromPeriod: fromPeriod,
          toDay: destination.substring(0, separator),
          toPeriod: int.parse(destination.substring(separator + 1)),
          subjectId: subject.id,
          destinationSubjectId: classItem.cells[destination],
        ));
  }

  String _slotLabel(ScheduleClass classItem, String slot) {
    final separator = slot.lastIndexOf('_');
    final day = slot.substring(0, separator);
    final period = int.parse(slot.substring(separator + 1));
    final target = classItem.subjectById(classItem.cells[slot]);
    return '$day · ${classTimes[period]} · ${target?.name ?? 'Vacía'}';
  }

  Widget _buildTasks({bool desktop = false}) {
    if (_user == null) {
      return desktop
          ? _DesktopSignInPrompt(
              title: 'Tareas y exámenes', onSignIn: _showAccount)
          : _SignInPrompt(onSignIn: _showAccount);
    }
    final classItem = _selectedClass;
    final visible = _tasks
        .where((task) =>
            (classItem == null ||
                task.scheduleId == null ||
                task.scheduleId == classItem.id) &&
            task.completed == _showTaskHistory)
        .toList();
    return Column(
      children: [
        _SectionHeader(
          title: _showTaskHistory ? 'Historial de tareas' : 'Pendientes',
          actionLabel: _showTaskHistory ? 'Ver pendientes' : 'Historial',
          compact: desktop,
          onAdd: desktop && classItem != null && classItem.subjects.isNotEmpty
              ? () => _editTask(
                    day: weekdays[_selectedDay],
                    subject: classItem.subjects.first.name,
                  )
              : null,
          onAction: () => setState(() => _showTaskHistory = !_showTaskHistory),
        ),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(
                  icon: Icons.checklist,
                  message: _showTaskHistory
                      ? 'Todavía no hay tareas completadas.'
                      : 'Tus tareas y exámenes aparecerán aquí.',
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = visible[index];
                      return _TaskCard(
                        task: task,
                        onToggle: (completed) => _perform(
                          () => _service.setTaskCompleted(task.id, completed),
                        ),
                        onEdit: () => _editTask(
                          day: task.day,
                          subject: task.subject,
                          task: task,
                        ),
                        onDelete: () => _deleteTask(task),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildReminders({bool desktop = false}) {
    if (_user == null) {
      return desktop
          ? _DesktopSignInPrompt(title: 'Recordatorios', onSignIn: _showAccount)
          : _SignInPrompt(onSignIn: _showAccount);
    }
    final visible = _reminders
        .where((reminder) => reminder.completed == _showReminderHistory)
        .toList();
    return Column(
      children: [
        _SectionHeader(
          title: _showReminderHistory
              ? 'Recordatorios completados'
              : 'Por recordar',
          actionLabel: _showReminderHistory ? 'Ver pendientes' : 'Historial',
          compact: desktop,
          onAdd: desktop ? () => _editReminder() : null,
          onAction: () =>
              setState(() => _showReminderHistory = !_showReminderHistory),
        ),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(
                  icon: Icons.bookmark_border,
                  message: _showReminderHistory
                      ? 'Todavía no hay recordatorios completados.'
                      : 'Guarda aquí temas o apuntes sin fecha.',
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final reminder = visible[index];
                      return _ReminderCard(
                        reminder: reminder,
                        onToggle: (completed) => _perform(
                          () => _service.setReminderCompleted(
                              reminder.id, completed),
                        ),
                        onEdit: () => _editReminder(reminder: reminder),
                        onDelete: () => _deleteReminder(reminder),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

String _colorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2)}';

class _TaskDamLogo extends StatelessWidget {
  const _TaskDamLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'icons/icon-192.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
}

class _ScheduleHeading extends StatelessWidget {
  const _ScheduleHeading({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 3,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '2º DAM  ·  HORARIO',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          'Selecciona una casilla vacía para añadir una asignatura.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
        ),
      ],
    );
  }
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF202B2E),
          border: Border.all(color: const Color(0xFF344246)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );
}

class _EmptyScheduleCell extends StatelessWidget {
  const _EmptyScheduleCell({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: const Color(0xFF263235),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Center(
              child:
                  Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      );
}

class _EmptyScheduleRow extends StatelessWidget {
  const _EmptyScheduleRow({super.key, required this.time, required this.onTap});

  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 105,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(time,
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ),
                Expanded(
                  child: Icon(Icons.add,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      );
}

class _WeeklyClassCell extends StatefulWidget {
  const _WeeklyClassCell({
    required this.subject,
    required this.onTap,
    required this.editing,
  });

  final ClassSubject subject;
  final VoidCallback onTap;
  final bool editing;

  @override
  State<_WeeklyClassCell> createState() => _WeeklyClassCellState();
}

class _WeeklyClassCellState extends State<_WeeklyClassCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(widget.subject.color);
    final radius = BorderRadius.circular(6);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          transform: Matrix4.diagonal3Values(
              _hovered ? 1.04 : 1.0, _hovered ? 1.04 : 1.0, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: widget.editing
                ? Border.all(color: Colors.white70, width: 1.5)
                : null,
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: color,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.subject.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      widget.subject.teacher,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeeklyBreakRow extends StatelessWidget {
  const _WeeklyBreakRow();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
            width: _desktopTimeColumnWidth,
            child: Padding(
              padding: EdgeInsets.all(3),
              child: Text('11:15 - 11:45', textAlign: TextAlign.center),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF343F41),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'RECREO',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ),
              ),
            ),
          ),
        ],
      );
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({
    required this.time,
    required this.subject,
    required this.onTap,
    required this.editing,
  });

  final String time;
  final ClassSubject subject;
  final VoidCallback onTap;
  final bool editing;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 5, color: _parseColor(subject.color)),
                SizedBox(
                  width: 100,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(time,
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subject.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text('Prof. ${subject.teacher}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    editing ? Icons.edit_outlined : Icons.add_circle_outline,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _BreakRow extends StatelessWidget {
  const _BreakRow();

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF343F41),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 11, horizontal: 16),
          child: Row(
            children: [
              SizedBox(width: 100, child: Text('11:15 - 11:45')),
              Icon(Icons.coffee_outlined, size: 18),
              SizedBox(width: 8),
              Text('RECREO',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ],
          ),
        ),
      );
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline,
                  size: 40, color: Color(0xFF46C4B2)),
              const SizedBox(height: 14),
              Text('Tus apuntes, solo para ti',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                  'Inicia sesión para sincronizar tareas y recordatorios con tu cuenta.'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.login),
                label: const Text('Iniciar sesión'),
              ),
            ],
          ),
        ),
      );
}

class _DesktopSignInPrompt extends StatelessWidget {
  const _DesktopSignInPrompt({required this.title, required this.onSignIn});

  final String title;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Icon(Icons.lock_outline, color: Color(0xFF46C4B2)),
              const SizedBox(height: 8),
              const Text('Inicia sesión para consultar y guardar tus apuntes.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.login),
                label: const Text('Iniciar sesión'),
              ),
            ],
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.onAdd,
    this.compact = false,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onAdd;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700))),
            if (onAdd != null)
              IconButton(
                tooltip: 'Añadir',
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            if (compact)
              IconButton(
                tooltip: actionLabel,
                onPressed: onAction,
                icon: const Icon(Icons.history),
              )
            else
              TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard(
      {required this.task,
      required this.onToggle,
      required this.onEdit,
      required this.onDelete});

  final TaskItem task;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final weekEnd = task.weekStart.add(const Duration(days: 4));
    final weekText =
        '${DateFormat('dd/MM').format(task.weekStart)} - ${DateFormat('dd/MM').format(weekEnd)}';
    return _AccentCard(
      color: _parseColor(task.color),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${task.day} · ${task.subject}',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (task.isExam) const _ExamTag(),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: task.completed
                      ? 'Reabrir tarea'
                      : 'Marcar como completada',
                  onPressed: () => onToggle(!task.completed),
                  icon: Icon(
                      task.completed ? Icons.undo : Icons.check_circle_outline),
                ),
                IconButton(
                    tooltip: 'Editar',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined)),
                IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 8),
              child: Text(task.message,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            const SizedBox(height: 7),
            Text('Semana $weekText',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard(
      {required this.reminder,
      required this.onToggle,
      required this.onEdit,
      required this.onDelete});

  final ReminderItem reminder;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _AccentCard(
        color: subjectColors[reminder.subject] ?? const Color(0xFF46C4B2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(reminder.subject,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(
                      tooltip: reminder.completed
                          ? 'Reabrir recordatorio'
                          : 'Marcar como completado',
                      onPressed: () => onToggle(!reminder.completed),
                      icon: Icon(reminder.completed
                          ? Icons.undo
                          : Icons.check_circle_outline)),
                  IconButton(
                      tooltip: 'Editar',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                      tooltip: 'Eliminar',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 8),
                child: Text(reminder.message),
              ),
            ],
          ),
        ),
      );
}

class _AccentCard extends StatelessWidget {
  const _AccentCard({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: color),
              Expanded(child: child),
            ],
          ),
        ),
      );
}

class _ExamTag extends StatelessWidget {
  const _ExamTag();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF9E5638),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('EXAMEN',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 38,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
}

Color _parseColor(String value) {
  if (value.startsWith('#') && value.length == 7) {
    return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
  }
  final match = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(value);
  if (match != null) {
    final red = int.parse(match.group(1)!);
    final green = int.parse(match.group(2)!);
    final blue = int.parse(match.group(3)!);
    return Color(0xFF000000 | (red << 16) | (green << 8) | blue);
  }
  return const Color(0xFF2787A0);
}
