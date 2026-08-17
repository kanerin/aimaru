import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/couple_service.dart';
import '../services/google_calendar_cache_service.dart';
import '../services/notification_settings_service.dart';
import '../services/settings_service.dart';
import '../services/theme_controller.dart';
import '../utils/app_theme.dart';
import '../widgets/anniversary_card.dart';
import '../widgets/days_off_card.dart';
import 'expenses_screen.dart';
import 'ics_import_screen.dart';
import 'trash_screen.dart';

const _reminderOptions = <int, String>{
  15:   '15分前',
  30:   '30分前',
  60:   '1時間前',
  180:  '3時間前',
  1440: '1日前',
};

class SettingsScreen extends StatefulWidget {
  final String coupleId;
  const SettingsScreen({super.key, required this.coupleId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _coupleService = CoupleService();
  final _settingsService = SettingsService();
  final _googleCalendarCache = GoogleCalendarCacheService();
  final _notificationSettingsService = NotificationSettingsService();

  String? _partnerName;
  CoupleModel? _couple;
  bool _showGoogleCalendar = false;
  bool _defaultSync = false;
  bool _showHolidays = true;
  bool _weekStartsMonday = false;
  bool _loadingPrefs = true;

  bool _notifyOnNewEvent = true;
  bool _remindersEnabled = true;
  int  _reminderMinutesBefore = 60;

  @override
  void initState() {
    super.initState();
    _loadPartner();
    _loadPrefs();
  }

  Future<void> _loadPartner() async {
    final couple = await _coupleService.getMyCouple();
    if (couple == null) return;
    final name = await _coupleService.getPartnerName(couple);
    if (mounted) {
      setState(() {
        _partnerName = name;
        _couple = couple;
      });
    }
  }

  Future<void> _loadPrefs() async {
    final show = await _settingsService.getShowGoogleCalendar();
    final sync = await _settingsService.getDefaultSyncGoogleCalendar();
    final holidays = await _settingsService.getShowHolidays();
    final weekStart = await _settingsService.getWeekStartsMonday();
    final notif = await _notificationSettingsService.get();
    if (mounted) {
      setState(() {
        _showGoogleCalendar = show;
        _defaultSync = sync;
        _showHolidays = holidays;
        _weekStartsMonday = weekStart;
        _notifyOnNewEvent = notif.notifyOnNewEvent;
        _remindersEnabled = notif.remindersEnabled;
        _reminderMinutesBefore = notif.reminderMinutesBefore;
        _loadingPrefs = false;
      });
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('ログアウトしますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _authService.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionLabel('プロフィール'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.navySurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(children: [
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.navyCard,
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null
                      ? const Icon(Icons.person, color: AppColors.textMuted)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.displayName ?? '', style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.cream,
                      )),
                      const SizedBox(height: 2),
                      Text(user?.email ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ]),
              if (_partnerName != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.hairline),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('💑', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('パートナー: $_partnerName', style: const TextStyle(fontSize: 13, color: AppColors.textSecond)),
                ]),
              ],
            ]),
          ),

          const SizedBox(height: 28),
          const _SectionLabel('記念日'),
          AnniversaryCard(
            coupleId: widget.coupleId,
            initialAnniversary: _couple?.anniversary,
            onSaved: (date) => setState(() {
              final couple = _couple;
              if (couple != null) {
                _couple = CoupleModel(
                  id: couple.id,
                  memberIds: couple.memberIds,
                  inviteCode: couple.inviteCode,
                  createdAt: couple.createdAt,
                  anniversary: date,
                  // 休みの設定を引き継がないと、記念日を保存しただけで
                  // 画面上の休み設定が既定値へ戻って見えてしまう
                  daysOff: couple.daysOff,
                  holidaysAreDaysOff: couple.holidaysAreDaysOff,
                );
              }
            }),
          ),

          const SizedBox(height: 28),
          const _SectionLabel('基本の休日'),
          DaysOffCard(
            coupleId: widget.coupleId,
            initialDaysOff: _couple?.daysOff ?? CoupleModel.defaultDaysOff,
            initialHolidaysAreDaysOff: _couple?.holidaysAreDaysOff ?? true,
            onSaved: (daysOff, holidaysAreDaysOff) => setState(() {
              final couple = _couple;
              if (couple != null) {
                _couple = CoupleModel(
                  id: couple.id,
                  memberIds: couple.memberIds,
                  inviteCode: couple.inviteCode,
                  createdAt: couple.createdAt,
                  anniversary: couple.anniversary,
                  daysOff: daysOff,
                  holidaysAreDaysOff: holidaysAreDaysOff,
                );
              }
            }),
          ),

          const SizedBox(height: 28),
          const _SectionLabel('表示'),
          if (_loadingPrefs)
            const _LoadingRow()
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairline),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('テーマカラー', style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                  )),
                  SizedBox(height: 10),
                  _AccentColorPicker(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SettingsSwitch(
              title: '祝日を表示',
              subtitle: 'カレンダーに日本の祝日を表示します',
              value: _showHolidays,
              onChanged: (v) async {
                setState(() => _showHolidays = v);
                await _settingsService.setShowHolidays(v);
              },
            ),
            const SizedBox(height: 12),
            _SettingsSwitch(
              title: '週の始まりを月曜日にする',
              subtitle: 'OFFの場合は日曜始まりで表示します',
              value: _weekStartsMonday,
              onChanged: (v) async {
                setState(() => _weekStartsMonday = v);
                await _settingsService.setWeekStartsMonday(v);
              },
            ),
          ],

          const SizedBox(height: 28),
          const _SectionLabel('カレンダー連携'),
          if (_loadingPrefs)
            const _LoadingRow()
          else ...[
            _SettingsSwitch(
              title: 'Googleカレンダーの予定を表示',
              subtitle: '自分と、連携済みのパートナーのGoogleカレンダーの予定をカレンダー画面に表示します',
              value: _showGoogleCalendar,
              onChanged: (v) async {
                setState(() => _showGoogleCalendar = v);
                await _settingsService.setShowGoogleCalendar(v);
                if (!v) {
                  // OFFにしたら自分のキャッシュ（パートナーに見えている分）も消す
                  await _googleCalendarCache.clearMyEvents(widget.coupleId);
                }
              },
            ),
            const SizedBox(height: 12),
            _SettingsSwitch(
              title: '予定作成時にGoogleカレンダーにも同期',
              subtitle: 'このアプリで新しく作った予定に、Googleカレンダー同期のデフォルト値を適用します（予定ごとに変更も可能）',
              value: _defaultSync,
              onChanged: (v) async {
                setState(() => _defaultSync = v);
                await _settingsService.setDefaultSyncGoogleCalendar(v);
              },
            ),
            const SizedBox(height: 12),
            _NavigationRow(
              title: '他のカレンダーから予定をインポート',
              subtitle: 'TimeTreeやGoogleカレンダーなどのiCal(.ics)形式のURL・テキストから予定を取り込みます',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => IcsImportScreen(coupleId: widget.coupleId)),
              ),
            ),
          ],

          const SizedBox(height: 28),
          const _SectionLabel('通知'),
          if (_loadingPrefs)
            const _LoadingRow()
          else ...[
            _SettingsSwitch(
              title: 'パートナーの予定登録を通知',
              subtitle: 'パートナーが新しい予定を追加したときにプッシュ通知でお知らせします',
              value: _notifyOnNewEvent,
              onChanged: (v) async {
                setState(() => _notifyOnNewEvent = v);
                await _notificationSettingsService.setNotifyOnNewEvent(v);
              },
            ),
            const SizedBox(height: 12),
            _SettingsSwitch(
              title: '予定のリマインダー通知',
              subtitle: '予定の開始前にプッシュ通知でお知らせします',
              value: _remindersEnabled,
              onChanged: (v) async {
                setState(() => _remindersEnabled = v);
                await _notificationSettingsService.setRemindersEnabled(v);
              },
            ),
            if (_remindersEnabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('通知するタイミング', style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                    )),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reminderOptions.entries.map((entry) {
                        final selected = _reminderMinutesBefore == entry.key;
                        return ChoiceChip(
                          label: Text(entry.value, style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white : AppColors.textSecond,
                          )),
                          selected: selected,
                          selectedColor: appAccent(context),
                          backgroundColor: AppColors.navy,
                          side: const BorderSide(color: AppColors.hairline),
                          onSelected: (_) async {
                            setState(() => _reminderMinutesBefore = entry.key);
                            await _notificationSettingsService.setReminderMinutesBefore(entry.key);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],

          const SizedBox(height: 28),
          const _SectionLabel('お金の記録'),
          _NavigationRow(
            title: '割り勘・立て替え',
            subtitle: 'デート代や買い物の立て替えを記録して、精算額を自動で計算します',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ExpensesScreen(
                coupleId: widget.coupleId,
                memberIds: _couple?.memberIds ?? const [],
                partnerName: _partnerName ?? 'パートナー',
              )),
            ),
          ),

          const SizedBox(height: 28),
          const _SectionLabel('データ管理'),
          _NavigationRow(
            title: 'ゴミ箱',
            subtitle: '削除した予定を30日間保管します。誤って消してしまっても復元できます',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TrashScreen(coupleId: widget.coupleId)),
            ),
          ),

          const SizedBox(height: 28),
          const _SectionLabel('アカウント'),
          Center(
            child: TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 16, color: Colors.redAccent),
              label: const Text('ログアウト', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: const TextStyle(
      fontSize: 11, letterSpacing: 1, color: AppColors.textMuted, fontWeight: FontWeight.w600,
    )),
  );
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: CircularProgressIndicator(color: appAccent(context)),
    ),
  );
}

class _SettingsSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
            )),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5)),
          ],
        ),
      ),
      Switch(value: value, onChanged: onChanged),
    ]),
  );
}

class _NavigationRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavigationRow({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
              )),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: AppColors.textMuted),
      ]),
    ),
  );
}

class _AccentColorPicker extends StatelessWidget {
  const _AccentColorPicker();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ThemeController.instance,
    builder: (context, _) => Wrap(
      spacing: 14,
      runSpacing: 10,
      children: AppColors.accentPresets.entries.map((entry) {
        final selected = ThemeController.instance.accentName == entry.key;
        return GestureDetector(
          onTap: () => ThemeController.instance.setAccentName(entry.key),
          child: Column(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: entry.value,
                  shape: BoxShape.circle,
                  border: selected ? Border.all(color: AppColors.textPrimary, width: 2) : null,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(entry.key, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
            ],
          ),
        );
      }).toList(),
    ),
  );
}
