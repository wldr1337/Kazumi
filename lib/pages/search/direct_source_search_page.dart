import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

/// 直接从已启用的片源规则搜索，不经过番剧资料库。
///
/// 搜索结果只有名称与来源，点击后直接解析播放线路并进入播放页。
/// 可选择搜索全部片源，或仅搜索指定的单个片源。
class DirectSourceSearchPage extends StatefulWidget {
  const DirectSourceSearchPage({super.key});

  @override
  State<DirectSourceSearchPage> createState() => _DirectSourceSearchPageState();
}

class _DirectSourceSearchPageState extends State<DirectSourceSearchPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// null 表示搜索全部片源，否则只搜索指定名称的片源。
  String? _selectedPluginName;
  bool _searching = false;
  String _keyword = '';
  List<_SourceGroup> _groups = <_SourceGroup>[];
  String? _playingSrc;

  List<Plugin> get _plugins =>
      List<Plugin>.of(inject<PluginsController>().pluginList);

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _input.text.trim();
    if (keyword.isEmpty || _searching) return;
    _focus.unfocus();

    final plugins = _plugins;
    final targets = _selectedPluginName == null
        ? plugins
        : plugins.where((p) => p.name == _selectedPluginName).toList();

    setState(() {
      _keyword = keyword;
      _searching = true;
      _groups = [for (final plugin in targets) _SourceGroup(plugin: plugin)];
    });

    await Future.wait([
      for (final group in _groups) _queryGroup(group, keyword),
    ]);

    if (!mounted) return;
    setState(() => _searching = false);
  }

  Future<void> _queryGroup(_SourceGroup group, String keyword) async {
    try {
      final response =
          await group.plugin.queryBangumi(keyword, shouldRethrow: true);
      if (!mounted) return;
      setState(() {
        group.items = response.data;
        group.status = response.data.isEmpty
            ? PluginSearchStatus.noResult
            : PluginSearchStatus.success;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is CaptchaRequiredException) {
          group.status = PluginSearchStatus.captcha;
        } else if (error is NoResultException) {
          group.status = PluginSearchStatus.noResult;
        } else {
          group.status = PluginSearchStatus.error;
        }
      });
    }
  }

  Future<void> _play(_SourceGroup group, SearchItem item) async {
    if (_playingSrc != null) return;
    setState(() => _playingSrc = item.src);
    try {
      final roads = await group.plugin.queryChapterRoads(item.src);
      if (!mounted) return;
      if (roads.isEmpty) {
        KazumiDialog.showToast(message: '未能获取播放列表');
        return;
      }
      final bangumiItem = BangumiItem(
        id: item.src.hashCode.abs(),
        type: 0,
        name: item.name,
        nameCn: item.name,
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: const <String, String>{},
        tags: const [],
        alias: <String>[],
        ratingScore: 0,
        votes: 0,
        votesCount: const [],
        info: '',
      );
      context.pushNamed(
        '/video/',
        arguments: OnlineVideoPlaybackArgs(
          bangumiItem: bangumiItem,
          plugin: group.plugin,
          title: item.name,
          src: item.src,
          roads: roads,
        ),
      );
    } catch (error) {
      if (mounted) {
        KazumiDialog.showToast(message: '未能获取播放列表，请重试或选择其他结果');
      }
    } finally {
      if (mounted) setState(() => _playingSrc = null);
    }
  }

  Future<void> _pickPlugin() async {
    if (_searching) return;
    _focus.unfocus();
    final plugins = _plugins;
    if (plugins.isEmpty) {
      KazumiDialog.showToast(message: '还没有可用的片源规则');
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('全部片源'),
              subtitle: const Text('并行搜索所有已启用片源'),
              selected: _selectedPluginName == null,
              selectedTileColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              onTap: () => Navigator.of(context).pop(null),
            ),
            for (final plugin in plugins)
              ListTile(
                leading: const Icon(Icons.source_rounded),
                title: Text(plugin.name),
                subtitle: Text(plugin.baseUrl),
                selected: _selectedPluginName == plugin.name,
                selectedTileColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                onTap: () => Navigator.of(context).pop(plugin.name),
              ),
          ],
        ),
      ),
    );

    if (result == _selectedPluginName) return;
    setState(() {
      _selectedPluginName = result;
      // 切换片源后清空旧结果，避免不同片源的结果混杂。
      _groups = const <_SourceGroup>[];
      _keyword = '';
    });
  }

  String get _searchHint {
    if (_selectedPluginName == null) return '输入关键词，直接搜索所有已启用片源';
    return '输入关键词，在 $_selectedPluginName 中搜索';
  }

  Widget _searchField() {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: _input,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        hintText: _searchHint,
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: '搜索',
          onPressed: _search,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text('从片源直接搜索')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _searchField(),
            const SizedBox(height: 12),
            _pluginPickerTile(),
            const SizedBox(height: 4),
            if (_keyword.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: GeneralEmptyState(
                  icon: Icons.travel_explore_rounded,
                  title: '输入关键词后直接在各片源中查找',
                ),
              )
            else if (_searching && !_hasAnyItems)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: LoadingIndicator(size: 40)),
              )
            else if (!_hasAnyItems)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: GeneralEmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有找到内容',
                ),
              )
            else
              for (final group in _groups) ..._groupWidgets(group),
          ],
        ),
      ),
    );
  }

  Widget _pluginPickerTile() {
    final theme = Theme.of(context);
    final label = _selectedPluginName ?? '全部片源';
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        leading: Icon(
          _selectedPluginName == null
              ? Icons.all_inclusive_rounded
              : Icons.source_rounded,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          '片源：$label',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          _selectedPluginName == null ? '点击可指定单个片源' : '点击可切换或搜索全部片源',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _pickPlugin,
      ),
    );
  }

  bool get _hasAnyItems => _groups.any((group) => group.items.isNotEmpty);

  List<Widget> _groupWidgets(_SourceGroup group) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                group.plugin.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              _statusLabel(group.status),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      if (group.items.isEmpty)
        const SizedBox.shrink()
      else
        for (final item in group.items) _resultTile(group, item),
    ];
  }

  Widget _resultTile(_SourceGroup group, SearchItem item) {
    final theme = Theme.of(context);
    final loading = _playingSrc == item.src;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          group.plugin.name,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.play_circle_outline_rounded,
                color: theme.colorScheme.primary,
              ),
        onTap: loading ? null : () => _play(group, item),
      ),
    );
  }

  String _statusLabel(PluginSearchStatus status) {
    return switch (status) {
      PluginSearchStatus.pending => '搜索中',
      PluginSearchStatus.success => '已找到',
      PluginSearchStatus.error => '搜索失败',
      PluginSearchStatus.noResult => '无结果',
      PluginSearchStatus.captcha => '需要验证',
    };
  }
}

class _SourceGroup {
  _SourceGroup({required this.plugin});

  final Plugin plugin;
  PluginSearchStatus status = PluginSearchStatus.pending;
  List<SearchItem> items = <SearchItem>[];
}
