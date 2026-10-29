import 'package:PiliPlus/models/mall/mall.dart';
import 'package:PiliPlus/models/mall/search.dart';
import 'package:material_ui/material_ui.dart';

class MallSearchFilters extends StatelessWidget {
  const MallSearchFilters({
    super.key,
    required this.options,
    required this.onChanged,
  });

  final MallSearchOptions options;
  final ValueChanged<MallSearchOptions> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Row(
      spacing: 8,
      children: [
        PopupMenuButton<MallSort>(
          tooltip: '搜索排序',
          initialValue: options.sort,
          onSelected: (sort) => onChanged(options.withSort(sort)),
          itemBuilder: (_) => [
            for (final sort in MallSort.values)
              PopupMenuItem(value: sort, child: Text(sort.label)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(options.sort.label),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
        FilterChip(
          tooltip: '价格筛选',
          selected: options.hasPriceRange,
          label: Text(options.priceLabel),
          onSelected: (_) async {
            final value = await showModalBottomSheet<MallSearchOptions>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _PriceRangeSheet(options: options),
            );
            if (context.mounted && value != null) onChanged(value);
          },
        ),
        if (!options.isDefault)
          TextButton(
            onPressed: () => onChanged(const MallSearchOptions()),
            child: const Text('重置筛选'),
          ),
      ],
    ),
  );
}

class _PriceRangeSheet extends StatefulWidget {
  const _PriceRangeSheet({required this.options});

  final MallSearchOptions options;

  @override
  State<_PriceRangeSheet> createState() => _PriceRangeSheetState();
}

class _PriceRangeSheetState extends State<_PriceRangeSheet> {
  final _form = GlobalKey<FormState>();
  late final _minimum = TextEditingController(text: widget.options.minimumYuan);
  late final _maximum = TextEditingController(text: widget.options.maximumYuan);

  String? _validate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final fen = mallYuanToFen(value.trim());
    if (fen == null) return '请输入非负金额，最多两位小数';
    return fen > 100000000000 ? '金额超出允许范围' : null;
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final minimum = mallYuanToFen(_minimum.text.trim());
    final maximum = mallYuanToFen(_maximum.text.trim());
    final result = MallSearchOptions(
      sort: widget.options.sort,
      minimumFen: minimum,
      maximumFen: maximum,
    );
    if (!result.isValid) {
      // The cross-field error is presented by the upper-bound validator.
      _form.currentState!.validate();
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('价格区间', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('mall-minimum-price'),
                controller: _minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                maxLength: 13,
                decoration: const InputDecoration(labelText: '最低价（元）'),
                validator: _validate,
              ),
              TextFormField(
                key: const ValueKey('mall-maximum-price'),
                controller: _maximum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                maxLength: 13,
                decoration: const InputDecoration(labelText: '最高价（元）'),
                validator: (value) {
                  final error = _validate(value);
                  if (error != null) return error;
                  final minimum = mallYuanToFen(_minimum.text.trim());
                  final maximum = mallYuanToFen(value?.trim());
                  return minimum != null && maximum != null && minimum > maximum
                      ? '最高价不能低于最低价'
                      : null;
                },
              ),
              const SizedBox(height: 8),
              const Text('按官方商品价格筛选，定金及最终成交价以官方页面为准。'),
              const SizedBox(height: 16),
              FilledButton(onPressed: _apply, child: const Text('应用价格区间')),
              TextButton(
                onPressed: () => Navigator.of(context).pop(
                  MallSearchOptions(sort: widget.options.sort),
                ),
                child: const Text('清除价格限制'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
