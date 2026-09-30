import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/schedule.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import 'edit_sheets.dart';

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
  List<TaskItem> _tasks = [];
  List<ReminderItem> _reminders = [];
  bool _loadingData = false;
  bool _showTaskHistory = false;
  bool _showReminderHistory = false;
  int _tab = 0;
  int _selectedDay = (DateTime.now().weekday - 1).clamp(0, 4).toInt();

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.auth.authStateChanges().listen((user) {
      if (!mounted) return;
      setState(() => _user = user);
      if (_user == null) {
        setState(() {
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
        _service.loadTasks(),
        _service.loadReminders(),
      ]);
      if (!mounted) return;
      setState(() {
        _tasks = results[0] as List<TaskItem>;
        _reminders = results[1] as List<ReminderItem>;
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
    final draft = await showModalBottomSheet<TaskDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TaskEditorSheet(
        day: day,
        subject: subject,
        task: task,
      ),
    );
    if (draft == null) return;
    await _perform(() => _service.saveTask(
          id: task?.id,
          day: draft.day,
          subject: draft.subject,
          message: draft.message,
          color:
              '#${subjectColors[draft.subject]!.toARGB32().toRadixString(16).substring(2)}',
          weekStart: draft.weekStart,
          isExam: draft.isExam,
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
      builder: (context) => ReminderEditorSheet(reminder: reminder),
    );
    if (draft == null) return;
    await _perform(() => _service.saveReminder(
          id: reminder?.id,
          subject: draft.subject,
          message: draft.message,
        ));
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

  Future<void> _deleteReminder(ReminderItem reminder) async {
    if (!await _confirmDelete('¿Eliminar este recordatorio?')) return;
    await _perform(() => _service.deleteReminder(reminder.id));
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Horario', 'Tareas y exámenes', 'Recordatorios'];
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TaskDAM', style: Theme.of(context).textTheme.titleLarge),
            Text(
              isDesktop
                  ? 'Horario semanal · Tareas · Recordatorios'
                  : titles[_tab],
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
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
      body: isDesktop
          ? _buildDesktopDashboard()
          : IndexedStack(
              index: _tab,
              children: [
                _buildSchedule(),
                _buildTasks(),
                _buildReminders(),
              ],
            ),
      floatingActionButton: !isDesktop && _tab == 1 && _user != null
          ? FloatingActionButton.extended(
              onPressed: () => _editTask(
                day: weekdays[_selectedDay],
                subject: scheduleByDay[weekdays[_selectedDay]]!.first,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Añadir tarea'),
            )
          : !isDesktop && _tab == 2 && _user != null
              ? FloatingActionButton.extended(
                  onPressed: () => _editReminder(),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir recordatorio'),
                )
              : null,
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.view_week_outlined), label: 'Horario'),
                NavigationDestination(
                    icon: Icon(Icons.checklist), label: 'Tareas'),
                NavigationDestination(
                    icon: Icon(Icons.bookmark_border), label: 'Recordatorios'),
              ],
            ),
    );
  }

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

  Widget _buildWeeklySchedule() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Horario semanal',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Pulsa una clase para añadir una tarea o examen.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 74),
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
                              ? _WeeklyBreakRow()
                              : Row(
                                  children: [
                                    SizedBox(
                                      width: 74,
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
                                            row < 3
                                                ? classTimes[row]
                                                : classTimes[row - 1],
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
                                        child: _WeeklyClassCell(
                                          subject: scheduleByDay[day]![
                                              row < 3 ? row : row - 1],
                                          teacher: teachers[scheduleByDay[day]![
                                              row < 3 ? row : row - 1]]!,
                                          onTap: () => _editTask(
                                            day: day,
                                            subject: scheduleByDay[day]![
                                                row < 3 ? row : row - 1],
                                          ),
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

  Widget _buildSchedule() {
    final day = weekdays[_selectedDay];
    final daySchedule = scheduleByDay[day]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text(
          '2º Desarrollo de Aplicaciones Multiplataforma',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pulsa una clase para apuntar una tarea o un examen.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 18),
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
        for (var index = 0; index < daySchedule.length; index++) ...[
          if (index == 3) ...[
            const SizedBox(height: 8),
            const _BreakRow(),
            const SizedBox(height: 8),
          ],
          _ClassRow(
            time: classTimes[index],
            subject: daySchedule[index],
            teacher: teachers[daySchedule[index]]!,
            onTap: () => _editTask(day: day, subject: daySchedule[index]),
          ),
          if (index < daySchedule.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildTasks({bool desktop = false}) {
    if (_user == null) {
      return desktop
          ? _DesktopSignInPrompt(
              title: 'Tareas y exámenes', onSignIn: _showAccount)
          : _SignInPrompt(onSignIn: _showAccount);
    }
    final visible =
        _tasks.where((task) => task.completed == _showTaskHistory).toList();
    return Column(
      children: [
        _SectionHeader(
          title: _showTaskHistory ? 'Historial de tareas' : 'Pendientes',
          actionLabel: _showTaskHistory ? 'Ver pendientes' : 'Historial',
          compact: desktop,
          onAdd: desktop
              ? () => _editTask(
                    day: weekdays[_selectedDay],
                    subject: scheduleByDay[weekdays[_selectedDay]]!.first,
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

class _WeeklyClassCell extends StatelessWidget {
  const _WeeklyClassCell({
    required this.subject,
    required this.teacher,
    required this.onTap,
  });

  final String subject;
  final String teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: subjectColors[subject],
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    teacher,
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
      );
}

class _WeeklyBreakRow extends StatelessWidget {
  const _WeeklyBreakRow();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
            width: 74,
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
    required this.teacher,
    required this.onTap,
  });

  final String time;
  final String subject;
  final String teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 5, color: subjectColors[subject]),
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
                        Text(subject,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text('Prof. $teacher',
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.add_circle_outline, size: 20),
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
