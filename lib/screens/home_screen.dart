import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/schedule.dart';
import '../models/schedule_class.dart';
import '../models/task.dart';
import '../services/google_calendar_service.dart';
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
  final GoogleCalendarService _calendarService = GoogleCalendarService();
  late User? _user = widget.auth.currentUser;
  StreamSubscription<User?>? _authSubscription;
  List<ScheduleClass> _classes = [];
  List<TaskItem> _tasks = [];
  List<ReminderItem> _reminders = [];
  List<ClassMember> _classMembers = [];
  List<TaskItem> _memberTasks = [];
  List<ReminderItem> _memberReminders = [];
  final Set<String> _addingMemberItems = {};
  final Set<String> _addedMemberItems = {};
  bool _loadingData = false;
  bool _loadingClassMembers = false;
  bool _loadingMemberItems = false;
  bool _calendarBusy = false;
  bool _showTaskHistory = false;
  bool _showReminderHistory = false;
  bool _showClassMembers = false;
  bool _showStandaloneCalendar = false;
  int _homeTab = 0;
  int _tab = 0;
  int _selectedDay = (DateTime.now().weekday - 1).clamp(0, 4).toInt();
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _calendarSelectedDate =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  String _calendarClassFilter = '__all__';
  String? _draggingCalendarTaskId;
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
        _calendarService.pauseForFirebaseSignOut();
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
        if (_calendarClassFilter != '__all__' &&
            !_classes.any((item) => item.id == _calendarClassFilter)) {
          _calendarClassFilter = '__all__';
        }
      });
    } catch (error) {
      _showMessage('No se pudieron cargar tus datos: $error');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _addCalendarTask() async {
    if (_user == null) {
      _showMessage('Inicia sesión para añadir tareas y exámenes.');
      await _showAccount();
      return;
    }
    if (_classes.isEmpty) {
      _showMessage('Crea o busca una clase antes de añadir una tarea.');
      return;
    }
    ScheduleClass? classItem;
    if (_calendarClassFilter != '__all__') {
      classItem = _classes
          .where((item) => item.id == _calendarClassFilter)
          .firstOrNull;
    } else if (_classes.length == 1) {
      classItem = _classes.single;
    } else {
      classItem = await showModalBottomSheet<ScheduleClass>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text('Elige una clase',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              for (final item in _classes)
                ListTile(
                  leading: const Icon(Icons.class_outlined),
                  title: Text(item.name),
                  subtitle: Text('${item.subjects.length} asignaturas'),
                  enabled: item.subjects.isNotEmpty,
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      );
    }
    if (!mounted || classItem == null) return;
    if (classItem.subjects.isEmpty) {
      _showMessage('Añade una asignatura a la clase antes de crear tareas.');
      return;
    }
    final selectedDate = _calendarSelectedDate;
    await _editTask(
      day: calendarWeekdays[selectedDate.weekday - 1],
      subject: classItem.subjects.first.name,
      weekStart: mondayOf(selectedDate),
      taskClass: classItem,
    );
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

  Future<void> _editSubjects() async {
    final classItem = _selectedClass;
    if (classItem == null || classItem.subjects.isEmpty) return;
    if (!await _ensureSignedIn('Inicia sesión para editar asignaturas.')) {
      return;
    }
    if (!mounted) return;
    final subject = await showModalBottomSheet<ClassSubject>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
              child: Text('Editar asignaturas',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final item in classItem.subjects)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: _parseColor(item.color),
                ),
                title: Text(item.name),
                subtitle: Text(item.teacher),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (!mounted || subject == null) return;
    final draft = await showModalBottomSheet<SubjectDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SubjectEditorSheet(subject: subject),
    );
    if (!mounted || draft == null) return;
    await _perform(() => _service.updateSubject(
          classId: classItem.id,
          subjectId: subject.id,
          name: draft.name,
          teacher: draft.teacher,
          color: _colorHex(draft.color),
        ));
  }

  Future<void> _editScheduleTimes() async {
    final classItem = _selectedClass;
    if (classItem == null) return;
    if (!await _ensureSignedIn('Inicia sesión para editar las horas.')) return;
    if (!mounted) return;
    final times = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          ScheduleTimesEditorSheet(initialTimes: classItem.times),
    );
    if (!mounted || times == null) return;
    await _perform(() => _service.updateScheduleTimes(
          classId: classItem.id,
          times: times,
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
                      onPressed: _calendarBusy
                        ? null
                        : () {
                          Navigator.pop(context);
                          unawaited(_toggleGoogleCalendar());
                        },
                      icon: Icon(_calendarService.isConnected
                        ? Icons.event_busy_outlined
                        : Icons.calendar_month_outlined),
                      label: Text(_calendarBusy
                        ? 'Conectando Calendar…'
                        : _calendarService.isConnected
                          ? 'Desconectar Google Calendar'
                          : 'Conectar Google Calendar'),
                    ),
                    const SizedBox(height: 12),
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

  Future<void> _toggleGoogleCalendar() async {
    final email = _user?.email;
    if (email == null || _calendarBusy) return;
    setState(() => _calendarBusy = true);
    try {
      if (_calendarService.isConnected) {
        await _calendarService.disconnect();
        _showMessage('Google Calendar desconectado.');
        return;
      }
      final connectedEmail = await _calendarService.connect(email);
      if (connectedEmail == null) return;
      for (final task in _tasks) {
        await _calendarService.syncTask(task, update: true);
      }
      _showMessage('Google Calendar conectado: $connectedEmail.');
    } catch (error) {
      _showMessage('No se pudo sincronizar Google Calendar: $error');
    } finally {
      if (mounted) setState(() => _calendarBusy = false);
    }
  }

  Future<void> _editTask({
    required String day,
    required String subject,
    TaskItem? task,
    DateTime? weekStart,
    ScheduleClass? taskClass,
  }) async {
    if (_user == null) {
      _showMessage('Inicia sesión para añadir tareas y exámenes.');
      await _showAccount();
      return;
    }
    final classItem = taskClass ??
        _selectedClass ??
        _classes
            .where((item) => item.id == task?.scheduleId)
            .firstOrNull;
    if (classItem == null && task == null) {
      _showMessage('Crea al menos una asignatura antes de añadir tareas.');
      return;
    }
    if (classItem?.subjects.isEmpty == true && task == null) {
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
        availableSubjects: classItem?.subjects ?? const [],
        task: task,
        weekStart: weekStart,
      ),
    );
    if (!mounted || draft == null) return;
    final selectedSubject = classItem?.subjects
        .where((item) => item.name == draft.subject)
        .firstOrNull;
    String? savedTaskId;
    await _perform(() async {
      savedTaskId = await _service.saveTask(
        id: task?.id,
        day: draft.day,
        subject: draft.subject,
        message: draft.message,
        color: selectedSubject?.color ?? task?.color ?? '#2787A0',
        weekStart: draft.weekStart,
        isExam: draft.isExam,
        scheduleId: task?.scheduleId ?? classItem?.id,
      );
    });
    if (savedTaskId != null && _calendarService.isConnected) {
      try {
        final savedTask = _tasks.firstWhere((item) => item.id == savedTaskId);
        await _calendarService.syncTask(savedTask, update: task != null);
      } catch (error) {
        _showMessage('La tarea se guardó, pero Calendar no se actualizó: $error');
      }
    }
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

  String _memberItemKey(String type, String id) =>
      '${_selectedClassId ?? ''}:${_selectedMemberId ?? ''}:$type:$id';

  Future<void> _addMemberTaskToSchedule(TaskItem task) async {
    final classItem = _selectedClass;
    final currentUser = _user;
    final memberId = _selectedMemberId;
    if (classItem == null ||
        currentUser == null ||
        memberId == null ||
        memberId == currentUser.uid) {
      return;
    }

    final key = _memberItemKey('task', task.id);
    if (_addingMemberItems.contains(key) || _addedMemberItems.contains(key)) {
      return;
    }
    setState(() => _addingMemberItems.add(key));
    String? savedTaskId;
    try {
      final subject = classItem.subjects
          .where((item) => item.name == task.subject)
          .firstOrNull;
      await _perform(() async {
        savedTaskId = await _service.saveTask(
          day: task.day,
          subject: task.subject,
          message: task.message,
          color: subject?.color ?? task.color,
          weekStart: task.weekStart,
          isExam: task.isExam,
          scheduleId: classItem.id,
        );
      });
      if (savedTaskId == null || !mounted) return;
      setState(() => _addedMemberItems.add(key));
      if (_calendarService.isConnected) {
        try {
          final savedTask = _tasks.firstWhere((item) => item.id == savedTaskId);
          await _calendarService.syncTask(savedTask, update: false);
        } catch (error) {
          _showMessage(
              'La tarea se agregó al horario, pero Google Calendar no se actualizó: $error');
        }
      }
    } finally {
      if (mounted) setState(() => _addingMemberItems.remove(key));
    }
  }

  Future<void> _addMemberReminderToSchedule(ReminderItem reminder) async {
    final classItem = _selectedClass;
    final currentUser = _user;
    final memberId = _selectedMemberId;
    if (classItem == null ||
        currentUser == null ||
        memberId == null ||
        memberId == currentUser.uid) {
      return;
    }

    final key = _memberItemKey('reminder', reminder.id);
    if (_addingMemberItems.contains(key) || _addedMemberItems.contains(key)) {
      return;
    }
    setState(() => _addingMemberItems.add(key));
    var saved = false;
    try {
      await _perform(() async {
        await _service.saveReminder(
          subject: reminder.subject,
          message: reminder.message,
          scheduleId: classItem.id,
        );
        saved = true;
      });
      if (saved && mounted) setState(() => _addedMemberItems.add(key));
    } finally {
      if (mounted) setState(() => _addingMemberItems.remove(key));
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
    await _perform(() async {
      if (_calendarService.isConnected) {
        await _calendarService.deleteTask(task.id);
      }
      await _service.deleteTask(task.id);
    });
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
                tooltip: _showStandaloneCalendar || _showClassMembers
                    ? 'Volver a la clase'
                    : 'Volver a mis clases',
                onPressed: () => setState(() {
                  if (_showStandaloneCalendar) {
                    _showStandaloneCalendar = false;
                  } else if (_showClassMembers) {
                    _showClassMembers = false;
                    _selectedMemberId = null;
                    _tab = 0;
                  } else {
                    _selectedClassId = null;
                    _editingSchedule = false;
                    _homeTab = 0;
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
                    activeClass == null || _showStandaloneCalendar
                        ? 'TaskDAM'
                        : activeClass.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    activeClass == null
                        ? _homeTab == 0
                            ? 'Mis clases'
                            : 'Calendario'
                        : _showStandaloneCalendar
                            ? 'Calendario'
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
          if (activeClass != null && !_showStandaloneCalendar)
            IconButton(
              tooltip: 'Abrir calendario',
              onPressed: () =>
                  setState(() => _showStandaloneCalendar = true),
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          if (activeClass != null && isDesktop && !_showStandaloneCalendar)
            IconButton(
              tooltip: 'Usuarios de la clase',
              onPressed: _openClassMembers,
              icon: const Icon(Icons.groups_outlined),
            ),
          if (activeClass != null && !_showStandaloneCalendar)
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
      body: _showStandaloneCalendar
          ? _buildCalendar()
          : activeClass == null
          ? _homeTab == 0
              ? _buildClassHome()
              : _buildCalendar()
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
      floatingActionButton: !_showStandaloneCalendar &&
              activeClass != null &&
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
      bottomNavigationBar: activeClass == null
          ? NavigationBar(
              selectedIndex: _homeTab,
              onDestinationSelected: (index) =>
                  setState(() => _homeTab = index),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.class_outlined), label: 'Mis clases'),
                NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    label: 'Calendario'),
              ],
            )
          : isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _showStandaloneCalendar ? 4 : _tab,
                  onDestinationSelected: (index) {
                    setState(() {
                      _showStandaloneCalendar = index == 4;
                      if (index < 4) {
                        _tab = index;
                        _showClassMembers = index == 3;
                      }
                    });
                    if (index == 3) unawaited(_loadClassMembers());
                  },
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.view_week_outlined), label: 'Horario'),
                    NavigationDestination(
                        icon: Icon(Icons.checklist), label: 'Tareas'),
                    NavigationDestination(
                        icon: Icon(Icons.bookmark_border),
                        label: 'Recordatorios'),
                    NavigationDestination(
                        icon: Icon(Icons.groups_outlined), label: 'Usuarios'),
                    NavigationDestination(
                        icon: Icon(Icons.calendar_month_outlined),
                        label: 'Calendario'),
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

  Widget _buildMemberNotes(ClassMember member) {
    final pendingTasks = tasksByDateProximity(
      _memberTasks.where((task) => !task.completed),
    );
    final completedTasks = tasksByDateProximity(
      _memberTasks.where((task) => task.completed),
    );
    final pendingReminders = remindersByCreationDate(
      _memberReminders.where((reminder) => !reminder.completed),
    );
    final completedReminders = remindersByCreationDate(
      _memberReminders.where((reminder) => reminder.completed),
    );

    return ListView(
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
            Text('Pendientes',
                style: Theme.of(context).textTheme.titleSmall),
            if (pendingTasks.isEmpty)
              const Text('No ha compartido tareas pendientes.')
            else
              for (final task in pendingTasks) ...[
                Card(
                  child: ListTile(
                    leading: Icon(task.isExam
                        ? Icons.fact_check_outlined
                        : Icons.checklist),
                    title: Text(task.subject),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${task.day} · ${task.message}'),
                        if (member.id != _user?.uid)
                          _memberItemButton(
                            key: _memberItemKey('task', task.id),
                            onPressed: () => _addMemberTaskToSchedule(task),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            const SizedBox(height: 12),
            Text('Completadas',
                style: Theme.of(context).textTheme.titleSmall),
            if (completedTasks.isEmpty)
              const Text('No ha compartido tareas completadas.')
            else
              for (final task in completedTasks) ...[
                Card(
                  child: ListTile(
                    leading: Icon(task.isExam
                        ? Icons.fact_check_outlined
                        : Icons.checklist),
                    title: Text(task.subject),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${task.day} · ${task.message}'),
                        if (member.id != _user?.uid)
                          _memberItemButton(
                            key: _memberItemKey('task', task.id),
                            onPressed: () => _addMemberTaskToSchedule(task),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.done_all, size: 18),
                  ),
                ),
              ],
            const SizedBox(height: 20),
            Text('Recordatorios',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Pendientes',
                style: Theme.of(context).textTheme.titleSmall),
            if (pendingReminders.isEmpty)
              const Text('No ha compartido recordatorios pendientes.')
            else
              for (final reminder in pendingReminders) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: Text(reminder.subject),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reminder.message),
                        if (member.id != _user?.uid)
                          _memberItemButton(
                            key: _memberItemKey('reminder', reminder.id),
                            onPressed: () =>
                                _addMemberReminderToSchedule(reminder),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            const SizedBox(height: 12),
            Text('Completados',
                style: Theme.of(context).textTheme.titleSmall),
            if (completedReminders.isEmpty)
              const Text('No ha compartido recordatorios completados.')
            else
              for (final reminder in completedReminders) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: Text(reminder.subject),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reminder.message),
                        if (member.id != _user?.uid)
                          _memberItemButton(
                            key: _memberItemKey('reminder', reminder.id),
                            onPressed: () =>
                                _addMemberReminderToSchedule(reminder),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.done_all, size: 18),
                  ),
                ),
              ],
          ],
        ],
      );
  }

  Widget _memberItemButton({
    required String key,
    required VoidCallback onPressed,
  }) {
    final adding = _addingMemberItems.contains(key);
    final added = _addedMemberItems.contains(key);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: adding || added ? null : onPressed,
        icon: adding
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(added ? Icons.check : Icons.add),
        label: Text(adding
            ? 'Agregando…'
            : added
                ? 'Agregado a tu horario'
                : 'Agregar a tu horario'),
      ),
    );
  }

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
                                          classItem.times[row < 3
                                              ? row
                                              : row - 1],
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
              if (classItem.subjects.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _editSubjects,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar asignaturas'),
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
              OutlinedButton.icon(
                onPressed: _editScheduleTimes,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: const Text('Editar horas'),
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
        time: classItem.times[period],
        onTap: () => _assignScheduleCell(day, period),
      );
    }
    return _ClassRow(
      time: classItem.times[period],
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
    return '$day · ${classItem.times[period]} · ${target?.name ?? 'Vacía'}';
  }

  Widget _buildCalendar() {
    if (_user == null) {
      return _SignInPrompt(onSignIn: _showAccount);
    }
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month);
    final lastDay = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0);
    final gridStart = mondayOf(firstDay);
    final visibleDays =
        ((lastDay.difference(gridStart).inDays + 1 + 6) ~/ 7) * 7;
    final monthTasks = _tasks
        .where((task) =>
            _calendarClassFilter == '__all__' ||
            task.scheduleId == _calendarClassFilter)
        .toList();
    final monthlyTaskCount = monthTasks.where((task) {
      final weekdayIndex = calendarWeekdays.indexOf(task.day);
      if (weekdayIndex < 0) return false;
      final taskDate =
          mondayOf(task.weekStart).add(Duration(days: weekdayIndex));
      return !taskDate.isBefore(firstDay) && !taskDate.isAfter(lastDay);
    }).length;
    const monthNames = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final screenWidth = MediaQuery.sizeOf(context).width;
    final gridWidth = screenWidth;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Mes anterior',
                onPressed: () => _moveCalendarMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${monthNames[_calendarMonth.month - 1]} ${_calendarMonth.year}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Mes siguiente',
                onPressed: () => _moveCalendarMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _calendarMonth = DateTime(now.year, now.month);
                    _calendarSelectedDate =
                        DateTime(now.year, now.month, now.day);
                  });
                },
                child: const Text('Hoy'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Añadir tarea',
                onPressed: _addCalendarTask,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _calendarClassFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Clase',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '__all__',
                      child: Text('Todas las clases'),
                    ),
                    for (final classItem in _classes)
                      DropdownMenuItem<String>(
                        value: classItem.id,
                        child: Text(classItem.name,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _calendarClassFilter = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$monthlyTaskCount ${monthlyTaskCount == 1 ? 'tarea' : 'tareas'}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: gridWidth,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        for (final day in const [
                          'LUN',
                          'MAR',
                          'MIÉ',
                          'JUE',
                          'VIE',
                          'SÁB',
                          'DOM'
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                day,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final rows = visibleDays ~/ 7;
                        return GridView.builder(
                          key: const ValueKey('calendar-month-grid'),
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisExtent:
                                (constraints.maxHeight - 8) / rows,
                          ),
                          itemCount: visibleDays,
                          itemBuilder: (context, index) {
                        final date = gridStart.add(Duration(days: index));
                        final isCurrentMonth =
                            date.month == _calendarMonth.month;
                        final isSelected =
                            dateKey(date) == dateKey(_calendarSelectedDate);
                        final isToday = dateKey(date) == dateKey(DateTime.now());
                        final visibleTaskCount = gridWidth < 700 ? 1 : 2;
                        final tasks = monthTasks.where((task) {
                          final weekdayIndex =
                              calendarWeekdays.indexOf(task.day);
                          if (weekdayIndex < 0) return false;
                          final taskDate = mondayOf(task.weekStart)
                              .add(Duration(days: weekdayIndex));
                          return dateKey(taskDate) == dateKey(date);
                        }).toList();
                        return DragTarget<TaskItem>(
                          key: ValueKey('calendar-drop-date-${dateKey(date)}'),
                          onAcceptWithDetails: (details) => unawaited(
                              _moveCalendarTask(details.data, date)),
                          builder: (context, candidates, rejected) {
                            final isDropTarget = candidates.isNotEmpty;
                            return Card(
                              key:
                                  ValueKey('calendar-date-${dateKey(date)}'),
                              margin: const EdgeInsets.all(2),
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(
                                  color: isDropTarget
                                      ? Theme.of(context).colorScheme.primary
                                      : isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                  width: isDropTarget || isSelected ? 2 : 0.6,
                                ),
                              ),
                              color: isDropTarget
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : isCurrentMonth
                                      ? Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLowest,
                              child: InkWell(
                                onTap: () {
                                  setState(
                                      () => _calendarSelectedDate = date);
                                  unawaited(
                                      _showCalendarDayTasks(date, tasks));
                                },
                                child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: isToday
                                          ? BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              shape: BoxShape.circle,
                                            )
                                          : null,
                                      child: Text(
                                        '${date.day}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: !isCurrentMonth
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                  : isToday
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .onPrimary
                                                      : null,
                                              fontWeight: isToday || isSelected
                                                  ? FontWeight.w800
                                                  : FontWeight.w500,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  for (final task in
                                      tasks.take(visibleTaskCount))
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 3),
                                      child: _CalendarMonthTask(
                                        task: task,
                                        draggable: true,
                                        isDragging:
                                            _draggingCalendarTaskId == task.id,
                                        onDragStarted: () => setState(
                                            () => _draggingCalendarTaskId =
                                                task.id),
                                        onDragEnd: (_) => setState(
                                            () => _draggingCalendarTaskId =
                                                null),
                                        onTap: () => _editTask(
                                          day: task.day,
                                          subject: task.subject,
                                          task: task,
                                        ),
                                      ),
                                    ),
                                  if (tasks.length > visibleTaskCount)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        key: ValueKey(
                                            'calendar-more-${dateKey(date)}'),
                                        onPressed: () {
                                          setState(() =>
                                              _calendarSelectedDate = date);
                                          _showCalendarDayTasks(date, tasks);
                                        },
                                        style: TextButton.styleFrom(
                                          minimumSize: Size.zero,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 2, vertical: 1),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: Text(
                                          '+${tasks.length - visibleTaskCount} más',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                        ),
                                      ),
                                    ),
                                ],
                                ),
                              ),
                              ),
                            );
                          },
                        );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _moveCalendarMonth(int offset) {
    setState(() {
      _calendarMonth =
          DateTime(_calendarMonth.year, _calendarMonth.month + offset);
      _calendarSelectedDate =
          DateTime(_calendarMonth.year, _calendarMonth.month);
    });
  }

  Future<void> _moveCalendarTask(TaskItem task, DateTime targetDate) async {
    final day = calendarWeekdays[targetDate.weekday - 1];
    final weekStart = mondayOf(targetDate);
    if (task.day == day && dateKey(mondayOf(task.weekStart)) == dateKey(weekStart)) {
      return;
    }
    if (_user == null) {
      _showMessage('Inicia sesión para mover tareas.');
      return;
    }

    try {
      await _service.saveTask(
        id: task.id,
        day: day,
        subject: task.subject,
        message: task.message,
        color: task.color,
        weekStart: weekStart,
        isExam: task.isExam,
        scheduleId: task.scheduleId,
      );
      if (!mounted) return;
      setState(() => _draggingCalendarTaskId = null);
      await _loadData();
      if (!mounted) return;
      _showMessage('Tarea movida al $day.');
      if (_calendarService.isConnected) {
        final movedTask = TaskItem(
          id: task.id,
          day: day,
          subject: task.subject,
          message: task.message,
          color: task.color,
          weekStart: weekStart,
          isExam: task.isExam,
          completed: task.completed,
          scheduleId: task.scheduleId,
        );
        try {
          await _calendarService.syncTask(movedTask, update: true);
        } catch (error) {
          _showMessage(
              'La tarea se movió, pero Google Calendar no se actualizó: $error');
        }
      }
    } catch (error) {
      _showMessage('No se pudo mover la tarea: $error');
    } finally {
      if (mounted) setState(() => _draggingCalendarTaskId = null);
    }
  }

  Future<void> _showCalendarDayTasks(
      DateTime date, List<TaskItem> tasks) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${calendarWeekdays[date.weekday - 1]} · ${DateFormat('dd/MM/yyyy').format(date)}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Text(
                    'No hay tareas para este día.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _CalendarMonthTask(
                        task: task,
                        onTap: () {
                          Navigator.pop(context);
                          _editTask(
                            day: task.day,
                            subject: task.subject,
                            task: task,
                          );
                        },
                        expanded: true,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasks({bool desktop = false}) {
    if (_user == null) {
      return desktop
          ? _DesktopSignInPrompt(
              title: 'Tareas y exámenes', onSignIn: _showAccount)
          : _SignInPrompt(onSignIn: _showAccount);
    }
    final classItem = _selectedClass;
    final visible = tasksByDateProximity(_tasks
        .where((task) =>
            (classItem == null ||
                task.scheduleId == null ||
                task.scheduleId == classItem.id) &&
            task.completed == _showTaskHistory));
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

class _CalendarMonthTask extends StatelessWidget {
  const _CalendarMonthTask({
    required this.task,
    required this.onTap,
    this.expanded = false,
    this.draggable = false,
    this.isDragging = false,
    this.onDragStarted,
    this.onDragEnd,
  });

  final TaskItem task;
  final VoidCallback onTap;
  final bool expanded;
  final bool draggable;
  final bool isDragging;
  final VoidCallback? onDragStarted;
  final ValueChanged<DraggableDetails>? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(task.color);
    if (expanded) {
      return Card(
        key: ValueKey('calendar-day-task-${task.id}'),
        color: color.withValues(alpha: 0.18),
        child: ListTile(
          leading: Icon(
            task.isExam ? Icons.school_outlined : Icons.checklist,
            color: color,
          ),
          title: Text(task.subject),
          subtitle: Text(task.message),
          trailing: task.completed
              ? const Icon(Icons.check_circle_outline)
              : null,
          onTap: onTap,
        ),
      );
    }
    Widget tile() => Material(
          color: color.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: Row(
                children: [
                  if (task.isExam)
                    const Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.school_outlined, size: 12),
                    ),
                  Expanded(
                    child: Text(
                      '${task.subject}: ${task.message}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                            decoration: task.completed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    if (!draggable) return tile();
    return Draggable<TaskItem>(
      key: ValueKey('calendar-drag-${task.id}'),
      data: task,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 190, child: tile()),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: tile()),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: isDragging ? 0.25 : 1,
        child: tile(),
      ),
    );
  }
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
    final weekEnd = task.weekStart.add(const Duration(days: 6));
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
