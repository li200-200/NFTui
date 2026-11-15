// ---------------------------------------------------------------------------
// 网络协议页面
//
// 入口：页脚的「软件使用协议」链接（登录 / 注册 / 充值 / 主页都有）。
// 本页跟其它页面一样没有标题栏，右上角保留同一排「返回 + 关闭」。
//
// 正文放在 kAgreementSections 里，是一组 (标题, 正文) 的列表。
// 要换成贵司正式法务版本，只需替换这个常量，排版代码不用动。
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:app_ui/theme.dart';
import 'package:app_ui/widgets/window_chrome.dart';

/// 协议的一个章节
class AgreementSection {
  const AgreementSection({required this.title, required this.body});

  final String title;
  final String body;
}

/// 协议正文。
/// 这是可直接使用的通用模板，上线前请替换为贵司法务确认过的版本。
const List<AgreementSection> kAgreementSections = <AgreementSection>[
  AgreementSection(
    title: '一、总则',
    body: '本《网络协议》（以下简称「本协议」）是您（以下称「用户」）与'
        '鸽鸽软件助手（以下称「本软件」）之间，就使用本软件所订立的法律协议。'
        '用户在安装、复制、下载或以其他方式使用本软件之前，应当仔细阅读本协议全部条款。'
        '一旦用户开始安装或使用本软件，即视为已阅读并同意受本协议全部条款的约束。'
        '若用户不同意本协议的任何内容，请立即停止安装、卸载并删除本软件。',
  ),
  AgreementSection(
    title: '二、软件许可与使用范围',
    body: '本软件按照现有形式向用户提供服务，用户可在单台计算机上安装、运行'
        '本软件的一个副本，用于个人或商业用途。未经本软件书面许可，用户不得'
        '对本软件进行反向工程、反编译、反汇编，不得删除或修改本软件中的任何'
        '权利管理信息，也不得将本软件出租、出借、二次分发或用于提供'
        '任何形式的商业网络服务。',
  ),
  AgreementSection(
    title: '三、账号、卡密与充值',
    body: '用户注册并使用本软件所提供的账号时应提供真实、准确、完整的个人资料，'
        '并对该账号下发生的一切行为承担全部责任。用户应妥善保管账号及密码，'
        '不得将账号、卡密转让、出借或与他人共享。'
        '因用户自身保管不善导致的账号被盗、卡密泄露，本软件不承担相应责任。'
        '充值成功后，除法律法规另有规定或因本软件原因导致服务无法提供的情形外，'
        '已购买的权益不予退还。',
  ),
  AgreementSection(
    title: '四、网络服务与数据传输',
    body: '用户理解并同意：本软件在运行过程中需要通过网络与本软件服务器进行连接，'
        '以实现账号登录、卡密校验、权益查询等功能；因此而产生的上网流量费用'
        '由用户自行向网络运营商支付。'
        '本软件仅为实现前述必要功能而收集和处理用户数据，'
        '不会在未经授权的情况下向第三方披露用户的个人隐私信息，'
        '但下列情形除外：'
        '（一）事先获得用户明确授权；'
        '（二）根据法律法规规定或司法机关、行政机关强制要求；'
        '（三）为保护国家、社会公共利益或他人合法权益所必需。',
  ),
  AgreementSection(
    title: '五、软件更新与维护',
    body: '为提升用户体验、修复缺陷或增强安全性，本软件可能不定期进行更新、'
        '升级或版本迭代。更新内容将依据本协议继续适用，'
        '若用户在保留现有版本的情况下继续使用本软件，视为对更新内容的接受。'
        '本软件可能因系统服务器的正常运行维护、故障检修、不可抗力等原因'
        '暂时中断服务。对由此造成的任何不便或损失，本软件在法律允许范围内'
        '予以免责。',
  ),
  AgreementSection(
    title: '六、用户行为规范',
    body: '用户承诺不会利用本软件从事或协助他人从事下列任一行为：'
        '（一）违反中华人民共和国法律法规的行为；'
        '（二）非法获取、删除、修改或增加他人计算机信息系统中的数据；'
        '（三）危害计算机信息网络安全、破坏本软件正常运行；'
        '（四）发布、传播含有病毒、木马或其他恶意程序的数据。'
        '一旦用户违反前述义务，本软件有权单方中断服务，'
        '并有权要求用户赔偿由此给本软件造成的损失。',
  ),
  AgreementSection(
    title: '七、免责声明',
    body: '本软件不对以下情形承担责任：'
        '（一）因用户自身操作失误、网络状况、通信链路故障等不可控原因'
        '导致的服务中断或数据丢失；'
        '（二）用户使用与本软件不匹配的其他软件所产生的后果；'
        '（三）因不可抗力导致的服务延迟、中断或终止。'
        '在法律允许的最大范围内，本软件不对使用本软件而产生的'
        '任何间接、附带、特殊或后果性的损害承担责任。',
  ),
  AgreementSection(
    title: '八、协议的变更与终止',
    body: '本软件有权在必要时对本协议条款进行修改，'
        '修改后的协议条款将在本软件或以适当方式公布。'
        '如用户继续使用本软件所提供的服务，视为对修改后的条款全部接受。'
        '若用户在长期使用过程中违反本协议的任一约定，'
        '本软件有权视情形单方面解除本协议并终止用户的全部服务。',
  ),
  AgreementSection(
    title: '九、争议解决与适用法律',
    body: '本协议的订立、执行、解释、效力及纠纷解决均适用'
        '中华人民共和国大陆地区法律。'
        '双方因本协议产生的纠纷由双方协商解决，'
        '协商不成的，任何一方均有权向本软件运营主体所在地有管辖权的人民法院'
        '提起诉讼。如果本协议的任何条款无论因何种原因完全或部分无效或不具有'
        '执行力，本协议的其余条款仍然有效并对双方具有约束力。',
  ),
  AgreementSection(
    title: '十、联系我们',
    body: '如您对本协议的内容有任何疑问、意见或建议，'
        '可通过本软件主界面右下角「联系领航」与我们联系，'
        '我们会在收到后尽快予以答复。',
  ),
];

// ---------------------------------------------------------------------------
// 打开协议页
// ---------------------------------------------------------------------------

/// 从任意页面弹出协议页。走的是根 Navigator，
/// 和主程序里「登录 ↔ 注册 ↔ 充值」的切换互不影响。
Future<void> openAgreementPage(BuildContext context) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondary,
      ) {
        return const AgreementPage();
      },
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondary,
        Widget child,
      ) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// 协议页本体
// ---------------------------------------------------------------------------

class AgreementPage extends StatelessWidget {
  const AgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(),
            const Divider(height: 1, thickness: 1, color: AuthColors.border),
            Expanded(child: _buildBody()),
          ],
        ),
        // 拖动层放最上面。这里必须用共用的 WindowDragLayer：
        // 它内部是 Listener，不进手势竞技场，所以下面的滚动列表照样能滚，
        // 同时空白处仍然可以拖窗口。
        // （早期这里写的是 Positioned.fill + GestureDetector(onPanStart)，
        //   那个写法会抢走指针，把竞技场里的点击/滚动全部判负，
        //   详见 window_chrome.dart 文件头的说明。）
        const Positioned.fill(child: WindowDragLayer()),
        // 右上角：返回 + 关闭，同一顶点左右平行
        Positioned(
          top: 6,
          right: 6,
          child: WindowControls(
            onBack: () => Navigator.of(context).maybePop(),
            // close 而不是 destroy：详见 widgets/window_chrome.dart 的说明。
            onClose: () => windowManager.close(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(26, 22, 26, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.description_outlined,
                size: 16,
                color: AuthColors.primary,
              ),
              SizedBox(width: 8),
              Text(
                '软件使用协议',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AuthColors.primary,
                  fontFamily: kFontFamily,
                  fontFamilyFallback: kFontFallback,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            '网络协议 · 最后更新 2026-09-21',
            style: TextStyle(
              fontSize: 11.5,
              color: AuthColors.textMuted,
              fontFamily: kFontFamily,
              fontFamilyFallback: kFontFallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Scrollbar(
      thumbVisibility: true,
      thickness: 5,
      radius: const Radius.circular(3),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(26, 12, 26, 24),
        itemCount: kAgreementSections.length,
        itemBuilder: (BuildContext context, int i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _SectionView(section: kAgreementSections[i]),
          );
        },
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final AgreementSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          section.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AuthColors.textPrimary,
            height: 1.6,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          section.body,
          textAlign: TextAlign.justify,
          style: const TextStyle(
            fontSize: 12,
            color: AuthColors.textHint,
            height: 1.85,
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
          ),
        ),
      ],
    );
  }
}
