// ---------------------------------------------------------------------------
// 右侧抽屉的三块内容（设置 / 个人中心 / 菜单）
//
// 这三个面板都是「只画界面、动作留空」—— 与左栏卡片的定位一致：本工程是界面
// 还原，设置项存不存盘、菜单项点下去做什么，都要等接入真实业务时再填。
//
// 【为什么三个面板放一个文件】
// 每个都只有几十行、彼此没有依赖、且都只被 drawer_content 的分支引用一次。
// 拆成三个文件会让「改一个设置项」变成「先找对文件」；放一起反而一眼看全。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/panel_controls.dart';
import 'package:app_ui/widgets/setting_table.dart';

// ---------------------------------------------------------------------------
// 设置
//
// 【布局：与左栏同一套控件 + 流式排布】
// 上一版在 311 宽的固定画布上按 config.ui 的 (x, y, w, h) 逐个 Positioned，
// 换来三个问题：控件之间只剩 0~2px（挤）、画布比抽屉窄 49px（右侧空白）、
// 输入框/勾选框/卡片标题都与左栏不是同一套样式。
//
// 这一版全部改掉：
//   · 卡片     → PanelGroupBox，标题与「登录区 / 信息区 / 选项区」同一个样式；
//   · 输入框   → LabeledField / BareField，与登录区「账户 / 密码」同一套视觉；
//   · 勾选框   → SwitchRow（需求指定「选择框使用开关样式」）；
//   · 按钮     → PanelButton，与「发送 / 登录」同高 23；
//   · 宽度     → 全部 Expanded 分配，卡片铺满抽屉内容区，右边缘对齐；
//   · 行距     → kSettingRowGap (8)，不再压到 0~2px。
//
// 【分组与控件归属与 config.ui 一致】
//   小号区   groupBox_xhq   tableWidget_xh（no/phone/token）
//                           + checkBox_qyxh（启用小号）+ pushButton_xhhq（获取）
//                           + label_xhts（*使用工具先获取小号数据）
//   滑块区   groupBox_hkq   label_hkts（*滑块需要配合使用工具）
//                           + pushButton_hklj（链接）+ checkBox_qyhk
//   上号器区 groupBox_shq   label_qz（前缀）+ lineEdit_shqz
//                           + pushButton_shqlj（链接）+ pushButton_shqdk（断开）
//   代理区   groupBox_4     label_dl（*滑块需要配合使用工具）
//                           + pushButton_dllj（链接）+ checkBox_qydl
//   通知区   groupBox       comboBox_tzxx（息知/wxpur/baerk）+ lineEdit_tz
//                           + pushButton_dllj_2（测试）+ checkBox_qydl_2
//
// 【代理区与通知区：所有控件同一行】
// 需求明确「通知区与代理区的组件都需要在同一行」。这两区的 .ui 几何本身就是
// 一行（y 全是 20），所以照办。难点是宽度预算：
//
//   抽屉内容区 311 − 卡片内边距 20 = 291
//
//   代理区：提示 131 + 6 + 按钮 64 + 6 + 开关「启用代理」约 100 = 307 > 291
//   通知区：下拉 + 输入框 + 6 + 按钮 64 + 6 + 开关 100 + 6 = 182 + 前两件
//
// 缩字号/内边距会与左栏控件不同源，不采用；改成让「可伸缩的那一件」用 Expanded
// 吃掉剩余宽度：代理区让提示 Expanded（附注缩放不损信息），通知区让下拉与输入框
// 按 3:4 分掉剩余宽度。这样一行必然装得下，且抽屉变宽时多出来的宽度给了信息量
// 最大的控件。
//
// 【上号器区：格式说明已并入标题，末位是「断开」按钮】
// config.ui 把 groupBox_shq 的高度从 71 收到 51，删掉 lineEdit_3（格式说明），
// 并把那段说明写进分组标题：
//     <string>上号器区 格式：前缀-手机号-密码-支付密码</string>
// 同时末位的 checkBox_qyxh_3 换成了 pushButton_shqdk（断开）。所以这一区是
// 「前缀输入框 + 链接 + 断开」同排，不再有开关。
// ---------------------------------------------------------------------------

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.checkBoxQyxh,
    required this.checkBoxQyhk,
    required this.checkBoxQydl,
    required this.checkBoxQydl2,
    required this.lineEditShqzController,
    required this.lineEditTzController,
    required this.comboBoxTzxx,
    required this.comboBoxTzxxItems,
    required this.subAccounts,
    required this.onCheckBoxQyxhChanged,
    required this.onCheckBoxQyhkChanged,
    required this.onCheckBoxQydlChanged,
    required this.onCheckBoxQydl2Changed,
    required this.onLineEditShqzChanged,
    required this.onLineEditTzChanged,
    required this.onComboBoxTzxxChanged,
    required this.onFetchSubAccounts,
    required this.onLinkSlider,
    required this.onLinkLoader,
    required this.onDisconnectLoader,
    required this.onLinkProxy,
    required this.onTestNotify,
    required this.subAccountSelected,
    required this.onToggleSubAccountSelection,
    required this.onSelectAllSubAccounts,
    required this.onDeleteSelectedSubAccounts,
  });

  /// 四个「启用 X」开关，逐项对应 .ui 的 checkBox：
  /// `checkBox_qyxh` / `checkBox_qyhk` / `checkBox_qydl` / `checkBox_qydl_2`。
  final bool checkBoxQyxh;
  final bool checkBoxQyhk;
  final bool checkBoxQydl;
  final bool checkBoxQydl2;

  /// 上号器区的「前缀」输入框（`lineEdit_shqz`）。
  ///
  /// 【必须由页面传入，不能在这里 new】
  /// 早先这里写的是 `TextEditingController(text: ...)` —— 每次 build 都造一个
  /// 新实例，用户刚输入的文字随下一次重建就没了。控制器归页面持有，这里只负责
  /// 接到输入框上。
  final TextEditingController lineEditShqzController;

  /// 通知区的地址输入框（`lineEdit_tz`）。
  final TextEditingController lineEditTzController;

  /// 通知区的通知方式下拉（`comboBox_tzxx`）。
  final String? comboBoxTzxx;
  final List<String> comboBoxTzxxItems;

  final List<SubAccount> subAccounts;

  final ValueChanged<bool> onCheckBoxQyxhChanged;
  final ValueChanged<bool> onCheckBoxQyhkChanged;
  final ValueChanged<bool> onCheckBoxQydlChanged;
  final ValueChanged<bool> onCheckBoxQydl2Changed;
  final ValueChanged<String> onLineEditShqzChanged;
  final ValueChanged<String> onLineEditTzChanged;
  final ValueChanged<String?> onComboBoxTzxxChanged;

  final VoidCallback onFetchSubAccounts;
  final VoidCallback onLinkSlider;
  final VoidCallback onLinkLoader;
  final VoidCallback onDisconnectLoader;
  final VoidCallback onLinkProxy;
  final VoidCallback onTestNotify;

  /// 小号表里被选中的行下标。
  ///
  /// 【为什么由页面持有而不是表格自己存】
  /// 「删除选中小号」要真的从 [subAccounts] 里删掉那几行 —— 数据在页面手里，
  /// 删除动作只能发生在那一层。表格自己存选中集合的话，页面还得再问它一遍，
  /// 多一次来回同步。
  final Set<int> subAccountSelected;

  final ValueChanged<int> onToggleSubAccountSelection;
  final VoidCallback onSelectAllSubAccounts;
  final VoidCallback onDeleteSelectedSubAccounts;

  @override
  Widget build(BuildContext context) {
    // 不再锁死画布宽度：卡片用 Column 顺序堆叠，宽度由抽屉内容区决定，
    // 于是「抽屉变宽 → 卡片跟着变宽」，右边缘始终与内边距对齐。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildSubAccountCard(),
        const SizedBox(height: kSettingCardGap),
        _buildSliderCard(),
        const SizedBox(height: kSettingCardGap),
        _buildLoaderCard(),
        const SizedBox(height: kSettingCardGap),
        _buildProxyCard(),
        const SizedBox(height: kSettingCardGap),
        _buildNotifyCard(),
      ],
    );
  }

  /// ① 小号区（`groupBox_xhq`）：表格 + 「启用小号 / 获取 / 提示」一行。
  Widget _buildSubAccountCard() {
    return PanelGroupBox(
      objectName: kGroupBoxXhq,
      title: '小号区',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SubAccountTable(
            key: const ValueKey<String>(kTableWidgetXh),
            rows: subAccounts,
            selected: subAccountSelected,
            onToggleSelection: onToggleSubAccountSelection,
            onSelectAll: onSelectAllSubAccounts,
            onDeleteSelected: onDeleteSelectedSubAccounts,
          ),
          const SizedBox(height: kSettingRowGap),
          // 开关、按钮、提示同排 —— 与 config.ui 的 checkBox_qyxh(0) /
          // pushButton_xhhq(70) / label_xhts(160) 的先后顺序一致。
          _ActionRow(
            switchObjectName: kCheckBoxQyxh,
            label: '启用小号',
            value: checkBoxQyxh,
            onChanged: onCheckBoxQyxhChanged,
            buttonObjectName: kPushButtonXhhq,
            buttonLabel: '获取',
            onPressed: onFetchSubAccounts,
            tipObjectName: kLabelXhts,
            tip: '*使用工具先获取小号数据',
          ),
        ],
      ),
    );
  }

  /// ② 滑块区（`groupBox_hkq`）：「启用滑块 / 链接 / 提示」一行。
  Widget _buildSliderCard() {
    return PanelGroupBox(
      objectName: kGroupBoxHkq,
      title: '滑块区',
      child: _ActionRow(
        switchObjectName: kCheckBoxQyhk,
        label: '启用滑块',
        value: checkBoxQyhk,
        onChanged: onCheckBoxQyhkChanged,
        buttonObjectName: kPushButtonHklj,
        buttonLabel: '链接',
        onPressed: onLinkSlider,
        tipObjectName: kLabelHkts,
        tip: '*滑块需要配合使用工具',
      ),
    );
  }

  /// ③ 上号器区（`groupBox_shq`）：前缀输入框 +「链接」+「断开」，**三件同一行**。
  ///
  /// 最新 .ui 把这一区从两行压成一行：高度 71 → 51，删掉 lineEdit_3，并把
  /// 「格式：前缀-手机号-密码-支付密码」并入分组标题。同时末位的勾选框换成了
  /// 「断开」按钮。所以这里是 label_qz + lineEdit_shqz + pushButton_shqlj
  /// + pushButton_shqdk，四者的 y 都是 20 —— 与 .ui 一样排成一行。
  ///
  /// 【前缀输入框为什么用窄标签格】
  /// 这一行要放下「标签 + 输入框 + 两个按钮」，两个按钮各 64 就是 128，加上
  /// 两个 6px 间距已占 140。标签格沿用左栏的 60 会把输入框挤到 90 以下。改成
  /// [kSettingLoaderLabelWidth]（44，「前缀」两字约 25px，仍有余量）。
  Widget _buildLoaderCard() {
    return PanelGroupBox(
      objectName: kGroupBoxShq,
      // 标题照抄 .ui 的 groupBox_shq.title（「上号器区」+ 格式说明）。
      // PanelGroupBox 的 SectionLabel 是单行省略，24 个字在抽屉里必然被截成
      // 「上号器区 格式：前缀-手机…」，所以这里把标题拆成两行交给卡片自己排。
      title: '上号器区',
      subtitle: '格式：前缀-手机号-密码-支付密码',
      child: SizedBox(
        // 整行高度取输入框的行高：按钮 23 在里面垂直居中，输入框与按钮等高。
        height: kRowHeight,
        child: Row(
          children: <Widget>[
            Expanded(
              child: LabeledField(
                key: const ValueKey<String>(kLineEditShqz),
                label: '前缀',
                controller: lineEditShqzController,
                hint: '上号前缀',
                labelWidth: kSettingLoaderLabelWidth,
                onChanged: onLineEditShqzChanged,
              ),
            ),
            const SizedBox(width: kSettingInlineGap),
            _CompactButton(
              objectName: kPushButtonShqlj,
              label: '链接',
              onPressed: onLinkLoader,
            ),
            const SizedBox(width: kSettingInlineGap),
            _CompactButton(
              objectName: kPushButtonShqdk,
              label: '断开',
              onPressed: onDisconnectLoader,
            ),
          ],
        ),
      ),
    );
  }

  /// ④ 代理区（`groupBox_4`）：提示 +「链接」+「启用代理」，**全部同一行**。
  ///
  /// 【宽度怎么塞进一行】
  /// 291 的内容区里：提示（13 个字约 131）+ 按钮 64 + 开关「启用代理」约 100
  /// + 两个 6px 间距 = 307，超了 16。所以提示用 Expanded 吃剩余宽度并按比例
  /// 缩放（[SettingTip] 的 inline 模式），按钮与开关保持固定 —— 缩的只是附注，
  /// 主控件尺寸不变，与其它卡片仍对齐。
  Widget _buildProxyCard() {
    return PanelGroupBox(
      objectName: kGroupBoxDl,
      title: '代理区',
      child: SizedBox(
        height: kRowHeight,
        child: Row(
          children: <Widget>[
            const Expanded(
              child: SettingTip(
                key: ValueKey<String>(kLabelDl),
                text: '*滑块需要配合使用工具',
                inline: true,
              ),
            ),
            const SizedBox(width: kSettingInlineGap),
            _CompactButton(
              objectName: kPushButtonDllj,
              label: '链接',
              onPressed: onLinkProxy,
            ),
            const SizedBox(width: kSettingInlineGap),
            SwitchRow(
              key: const ValueKey<String>(kCheckBoxQydl),
              label: '启用代理',
              value: checkBoxQydl,
              onChanged: onCheckBoxQydlChanged,
            ),
          ],
        ),
      ),
    );
  }

  /// ⑤ 通知区（`groupBox`）：下拉 + 输入框 +「测试」+「启用代理」，**全部同一行**。
  ///
  /// 【四件同排的宽度怎么算】
  /// 内容区 291。固定项：按钮 64 + 三个 6px 间距 18 = 82，剩 209 给「下拉 +
  /// 输入框 + 开关」。开关「启用代理」是 4 个字 + 32 轨道 + 8 间距 ≈ 96，于是
  /// 下拉 + 输入框只剩 113。
  ///
  /// 上一版按 3:4 分给下拉 48 —— 实测被压成「息...」：DropdownButton 内部还有
  /// 一个 24 宽的箭头图标槽，48 扣掉它只剩 24，连「息知」两个字都放不下。
  /// 所以下拉改成按内容定宽（[kSettingNotifyComboWidth] = 72，够放「wxpur」
  /// 这种 5 字符 + 箭头），输入框吃掉剩下的全部宽度 —— 它装的是地址，越长越好。
  Widget _buildNotifyCard() {
    return PanelGroupBox(
      objectName: kGroupBoxTz,
      title: '通知区',
      child: SizedBox(
        height: kRowHeight,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: kSettingNotifyComboWidth,
              child: PanelDropdown(
                key: const ValueKey<String>(kComboBoxTzxx),
                value: comboBoxTzxx,
                items: comboBoxTzxxItems,
                onChanged: onComboBoxTzxxChanged,
              ),
            ),
            const SizedBox(width: kSettingInlineGap),
            Expanded(
              child: BareField(
                key: const ValueKey<String>(kLineEditTz),
                controller: lineEditTzController,
                hint: '通知地址',
                center: false,
                onChanged: onLineEditTzChanged,
              ),
            ),
            const SizedBox(width: kSettingInlineGap),
            _CompactButton(
              objectName: kPushButtonDllj2,
              label: '测试',
              onPressed: onTestNotify,
            ),
            const SizedBox(width: kSettingInlineGap),
            SwitchRow(
              key: const ValueKey<String>(kCheckBoxQydl2),
              label: '启用代理',
              value: checkBoxQydl2,
              onChanged: onCheckBoxQydl2Changed,
            ),
          ],
        ),
      ),
    );
  }
}

/// 固定 64x23 的紧凑按钮，带 .ui 的 objectName。
///
/// 【为什么单独包一层】
/// 设置页里「链接 / 断开 / 测试 / 获取」四个按钮尺寸完全一致（64x23），只有文案
/// 与回调不同。写成四份 SizedBox + PanelButton 的话，宽度会各自漂移 —— 这一版
/// 的宽度就调过三次（72 → 64）。收成一处之后改宽度只改一个地方。
///
/// Key 挂在 SizedBox 上而不是 PanelButton 上：测试量的是「按钮占多大地方」，
/// 外层的 64x23 才是它在地面上的尺寸。
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.objectName,
    required this.label,
    required this.onPressed,
  });

  /// .ui 里这个 QPushButton 的 objectName。
  final String objectName;

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey<String>(objectName),
      width: kSettingActionButtonWidth,
      height: kCompactButtonHeight,
      child: PanelButton(
        label: label,
        height: kCompactButtonHeight,
        onPressed: onPressed,
      ),
    );
  }
}

/// 「开关 + 按钮 + 提示」三件同排的一行。
///
/// 【为什么抽成一个组件】
/// 小号区与滑块区这一排的结构完全相同（开关贴左、按钮居中偏右、提示吃掉剩余
/// 宽度），只有文案与回调不同。写成两份 Row 的话，「按钮宽度」「间距」「提示如何
/// 收缩」这些规则会在两处各自漂移 —— 之前正是这样：小号区把提示单独放了一行，
/// 另一区没有提示，于是两张卡片的高度与对齐各不相同。
///
/// 【提示为什么用 FittedBox 而不是折行】
/// 这一排的高度被开关锁在 [kRowHeight]（30）。提示若折成两行就会把整排顶到 40+，
/// 卡片的高度差又回来了。缩放 0.95~0.98 在 12 号字上肉眼分辨不出，折行却一眼
/// 就能看出「这排比别的排高」。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.switchObjectName,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.buttonObjectName,
    required this.buttonLabel,
    required this.onPressed,
    this.tipObjectName,
    this.tip,
  });

  /// 开关在 .ui 里的 objectName（`checkBox_qyxh` / `checkBox_qyhk`）。
  final String switchObjectName;

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 按钮在 .ui 里的 objectName（`pushButton_xhhq` / `pushButton_hklj`）。
  final String buttonObjectName;

  final String buttonLabel;
  final VoidCallback onPressed;

  /// 提示在 .ui 里的 objectName（`label_xhts` / `label_hkts`）。
  final String? tipObjectName;

  /// 说明文字。为空时按钮直接贴右端。
  final String? tip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 高度取开关的行高：按钮 23 在里面垂直居中，整排高度不被按钮左右。
      height: kRowHeight,
      child: Row(
        children: <Widget>[
          SwitchRow(
            key: ValueKey<String>(switchObjectName),
            label: label,
            value: value,
            onChanged: onChanged,
          ),
          const SizedBox(width: kSettingInlineGap),
          _CompactButton(
            objectName: buttonObjectName,
            label: buttonLabel,
            onPressed: onPressed,
          ),
          if (tip == null)
            const Spacer()
          else ...<Widget>[
            const SizedBox(width: kSettingInlineGap),
            // Expanded 让提示吃掉按钮右侧的全部宽度；inline: true 表示
            // 「单行 + 自动缩放」，绝不折行撑高这一排。
            Expanded(
              child: SettingTip(
                key: tipObjectName == null
                    ? null
                    : ValueKey<String>(tipObjectName!),
                text: tip!,
                inline: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 个人中心
// ---------------------------------------------------------------------------

class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.account,
    required this.onLogout,
  });

  /// 当前登录账号（空串表示未登录）。
  final String account;

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = account.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            // 头像：没有真实图片，用首字母占位。
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WorkColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: WorkColors.primary, width: 1),
              ),
              child: Text(
                loggedIn ? account.characters.first.toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: WorkColors.primary,
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    loggedIn ? account : '未登录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kFontTitle,
                      fontWeight: FontWeight.w600,
                      color: WorkColors.textPrimary,
                      fontFamily: kFontFamily,
                      fontFamilyFallback: kFontFallback,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loggedIn ? '已登录' : '请先在左栏登录',
                    style: const TextStyle(
                      fontSize: kFontHint,
                      color: WorkColors.textMuted,
                      fontFamily: kFontFamily,
                      fontFamilyFallback: kFontFallback,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 「退出登录」不做成整行通栏：260 的抽屉里通栏按钮有 232 宽，而文字只有
        // 4 个字 —— 按钮会被拉成一条横杠。改成按内容定宽（96），贴左对齐。
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: kProfileLogoutWidth,
            child: PanelButton(
              label: '退出登录',
              height: kCompactButtonHeight,
              // 未登录时没有可退的 —— 用 onPressed: null 表达禁用。
              onPressed: loggedIn ? onLogout : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 菜单
// ---------------------------------------------------------------------------

/// 菜单项：图标 + 文案 + 回调。
class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: kHoverDuration,
          curve: Curves.easeOut,
          height: kRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _hover
                ? WorkColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                widget.icon,
                size: kNavIconSize,
                color: _hover ? WorkColors.primary : WorkColors.textHint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: kFontBody,
                    color: _hover
                        ? WorkColors.primary
                        : WorkColors.textPrimary,
                    fontFamily: kFontFamily,
                    fontFamilyFallback: kFontFallback,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MenuPanel extends StatelessWidget {
  const MenuPanel({
    super.key,
    required this.onOpenDocs,
    required this.onOpenLogs,
    required this.onCheckUpdate,
    required this.onAbout,
  });

  final VoidCallback onOpenDocs;
  final VoidCallback onOpenLogs;
  final VoidCallback onCheckUpdate;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    // 【为什么加条目间距】
    // 抽屉只有 200 宽，菜单项是「26 图标 + 8 + 文字」的一行，本身高度 30。
    // 四条紧贴着排下来是一整块灰白，看不出是四个可点的独立项。加 2px 间距
    // 之后每条都有自己的边界，悬停高亮也不会连成一片。
    //
    // 用 Column + SizedBox 而不是 ListView.separated：只有四条固定项，
    // 不需要懒加载，也不希望它自己滚（抽屉外层已经有 SingleChildScrollView）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MenuItem(
          icon: Icons.menu_book_outlined,
          label: '使用说明',
          onTap: onOpenDocs,
        ),
        const SizedBox(height: kMenuItemGap),
        _MenuItem(
          icon: Icons.description_outlined,
          label: '运行日志',
          onTap: onOpenLogs,
        ),
        const SizedBox(height: kMenuItemGap),
        _MenuItem(
          icon: Icons.system_update_alt,
          label: '检查更新',
          onTap: onCheckUpdate,
        ),
        const SizedBox(height: kMenuItemGap),
        _MenuItem(
          icon: Icons.info_outline,
          label: '关于',
          onTap: onAbout,
        ),
      ],
    );
  }
}
