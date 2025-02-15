import 'package:card_swiper/card_swiper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:polkawallet_plugin_karura/pages/governanceNew/govExternalLinks.dart';
import 'package:polkawallet_plugin_karura/pages/governanceNew/proposalPanel.dart';
import 'package:polkawallet_plugin_karura/pages/governanceNew/referendumPanel.dart';
import 'package:polkawallet_plugin_karura/polkawallet_plugin_karura.dart';
import 'package:polkawallet_plugin_karura/utils/i18n/index.dart';
import 'package:polkawallet_sdk/api/types/gov/genExternalLinksParams.dart';
import 'package:polkawallet_sdk/api/types/gov/proposalInfoData.dart';
import 'package:polkawallet_sdk/api/types/gov/referendumInfoData.dart';
import 'package:polkawallet_sdk/storage/keyring.dart';
import 'package:polkawallet_sdk/utils/i18n.dart';
import 'package:polkawallet_ui/components/addressIcon.dart';
import 'package:polkawallet_ui/components/connectionChecker.dart';
import 'package:polkawallet_ui/components/infoItemRow.dart';
import 'package:polkawallet_ui/components/v3/plugin/pluginAccountInfoAction.dart';
import 'package:polkawallet_ui/components/v3/plugin/pluginButton.dart';
import 'package:polkawallet_ui/components/v3/plugin/pluginInfoItem.dart';
import 'package:polkawallet_ui/components/v3/plugin/pluginScaffold.dart';
import 'package:polkawallet_ui/components/v3/plugin/pluginTabCard.dart';
import 'package:polkawallet_ui/components/v3/plugin/pluginTextTag.dart';
import 'package:polkawallet_ui/components/v3/plugin/pluginTxButton.dart';
import 'package:polkawallet_ui/pages/v3/txConfirmPage.dart';
import 'package:polkawallet_ui/utils/consts.dart';
import 'package:polkawallet_ui/utils/format.dart';
import 'package:polkawallet_ui/utils/i18n.dart';
import 'package:polkawallet_ui/utils/index.dart';
import 'package:sticky_headers/sticky_headers.dart';

class GovernancePage extends StatefulWidget {
  GovernancePage(this.plugin, this.keyring, {Key? key}) : super(key: key);
  final PluginKarura plugin;
  final Keyring keyring;

  static const String route = '/governance/index';

  @override
  State<GovernancePage> createState() => _GovernancePageState();
}

class _GovernancePageState extends State<GovernancePage> {
  List _locks = [];
  int _tabIndex = 0;
  final GlobalKey<RefreshIndicatorState> _refreshKey =
      new GlobalKey<RefreshIndicatorState>();

  final Map<String, List> _links = {};
  bool isLoading = false;

  Future<void> _queryDemocracyLocks() async {
    final List? locks = await widget.plugin.sdk.api.gov
        .getDemocracyLocks(widget.keyring.current.address!);
    if (locks == null) return;

    widget.plugin.service!.gov.queryReferendumStatus(
        locks.map((e) => int.parse(e['referendumId'])).toList());

    if (mounted) {
      setState(() {
        _locks = locks;
      });
    }
  }

  Future<List?> _getExternalLinks(BigInt? id, String type) async {
    if (_links[id] != null) return _links[id];

    final List? res = await widget.plugin.sdk.api.gov.getExternalLinks(
      GenExternalLinksParams.fromJson({'data': id.toString(), 'type': type}),
    );
    if (res != null) {
      setState(() {
        _links['$type===${id.toString()}'] = res;
      });
    }
    return res;
  }

  Future<void> _fetchReferendums() async {
    setState(() {
      isLoading = true;
    });

    if (widget.plugin.sdk.api.connectedNode == null) {
      return;
    }
    widget.plugin.service!.gov.getReferendumVoteConvictions();
    final ls = await widget.plugin.service!.gov.queryReferendums();
    ls.forEach((e) {
      _getExternalLinks(e.index, 'referendum');
    });

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _fetchProposalsData() async {
    if (widget.plugin.sdk.api.connectedNode == null) {
      return;
    }
    setState(() {
      isLoading = true;
    });
    final ls = await widget.plugin.service!.gov.queryProposals();
    ls.forEach((e) {
      _getExternalLinks(BigInt.parse(e.index), 'proposal');
    });
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _fetchExternal() async {
    await widget.plugin.service!.gov.queryExternal();
  }

  Future<void> _freshData() async {
    if (widget.plugin.sdk.api.connectedNode != null) {
      widget.plugin.service!.gov.unsubscribeBestNumber();
      widget.plugin.service!.gov.subscribeBestNumber();
    }

    await _queryDemocracyLocks();
    if (_tabIndex == 0) {
      await _fetchReferendums();
    } else {
      _fetchReferendums();
    }
    if (_tabIndex == 1) {
      await _fetchProposalsData();
    } else {
      _fetchProposalsData();
    }

    _fetchExternal();
  }

  @override
  void dispose() {
    widget.plugin.service!.gov.unsubscribeBestNumber();

    super.dispose();
  }

  void _onUnlock(List<String> ids) {
    final dic = I18n.of(context)!.getDic(i18n_full_dic_karura, 'gov')!;
    _unlockTx(dic['democracy.unlock'], ids);
  }

  void _submitCancelVote(int id) {
    final govDic = I18n.of(context)!.getDic(i18n_full_dic_karura, 'gov')!;
    _unlockTx(govDic['vote.remove'], ["$id"]);
  }

  void _unlockTx(String? txTitle, List<String> ids) async {
    final txs = ids
        .map((e) => 'api.tx.democracy.removeVote(${BigInt.parse(e)})')
        .toList();
    txs.add('api.tx.democracy.unlock("${widget.keyring.current.address}")');
    final params = TxConfirmParams(
      txTitle: txTitle,
      module: 'utility',
      call: 'batch',
      txDisplay: {
        "actions": ['democracy.removeVote', 'democracy.unlock'],
      },
      params: [],
      rawParams: '[[${txs.join(',')}]]',
      isPlugin: true,
    );
    final res = await Navigator.of(context)
        .pushNamed(TxConfirmPage.route, arguments: params);
    if (res != null) {
      _refreshKey.currentState!.show();
    }
  }

  Future<void> _onSecondsTx(ProposalInfoData proposal) async {
    final dic = I18n.of(context)!.getDic(i18n_full_dic_karura, 'gov')!;
    final TxConfirmParams params = TxConfirmParams(
      module: 'democracy',
      call: 'second',
      txTitle: dic['proposal.second'],
      txDisplay: {
        dic["proposal"]: '#${BigInt.parse(proposal.index.toString()).toInt()}',
        "seconds": proposal.seconds!.length,
      },
      params: [
        BigInt.parse(proposal.index.toString()).toInt(),
        proposal.seconds!.length,
      ],
      isPlugin: true,
    );

    final res = await Navigator.of(context)
        .pushNamed(TxConfirmPage.route, arguments: params);
    if (res as bool? ?? false) {
      _refreshKey.currentState!.show();
    }
  }

  Widget buildHeaderView(List<dynamic> locks) {
    if (locks.length == 0) {
      return Container();
    }
    final dic = I18n.of(context)!.getDic(i18n_full_dic_karura, 'gov')!;
    final bestNumber = widget.plugin.store!.gov.bestNumber;
    final decimals = widget.plugin.networkState.tokenDecimals![0];
    final symbol = widget.plugin.networkState.tokenSymbol![0];
    double maxLockAmount = 0, maxUnlockAmount = 0;
    final List<String> unLockIds = [];
    for (int index = 0; index < locks.length; index++) {
      var unlockAt = locks[index]['unlockAt'];
      final amount = Fmt.balanceDouble(
        locks[index]!['balance'].toString(),
        decimals,
      );
      if (unlockAt != "0") {
        BigInt endLeft;
        try {
          endLeft = BigInt.parse("${unlockAt.toString()}") - bestNumber;
        } catch (e) {
          endLeft = BigInt.parse("0x${unlockAt.toString()}") - bestNumber;
        }
        if (endLeft.toInt() <= 0) {
          unLockIds.add(locks[index]!['referendumId']);
          if (amount > maxUnlockAmount) {
            maxUnlockAmount = amount;
          }
          continue;
        }
      }
      if (amount > maxLockAmount) {
        maxLockAmount = amount;
      }
    }
    final redeemable = maxUnlockAmount - maxLockAmount;

    final style =
        Theme.of(context).textTheme.headline5?.copyWith(color: Colors.white);
    return Column(
      children: [
        PluginTextTag(
          margin: EdgeInsets.only(left: 16),
          title: dic['v3.myStats']!,
        ),
        Container(
            height: redeemable > 0 ? 147 : 127,
            margin: EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: PluginColorsDark.cardColor,
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8))),
            child: Stack(
              children: [
                Container(
                    height: 127,
                    child: Swiper(
                      itemCount: locks.length,
                      itemWidth: double.infinity,
                      loop: false,
                      itemBuilder: (BuildContext context, int index) {
                        var unlockAt = locks[index]['unlockAt'];
                        final int blockDuration =
                            widget.plugin.store!.earn.blockDuration;
                        if (unlockAt == "0") {
                          widget.plugin.store!.gov.referendums!
                              .forEach((element) {
                            if (element.userVoted != null &&
                                element.index ==
                                    BigInt.parse(
                                        locks[index]['referendumId'])) {
                              unlockAt = element.status!['end'];
                              if (element.userVoted!['vote']['conviction'] !=
                                  'None') {
                                final String conviction =
                                    (element.userVoted!['vote']['conviction']
                                            as String)
                                        .substring(6, 7);
                                final con = widget
                                    .plugin.store!.gov.voteConvictions!
                                    .where((element) =>
                                        element['value'] ==
                                        int.parse(conviction))
                                    .first["period"];
                                unlockAt = unlockAt +
                                    double.parse(con).toInt() * 24 * 600;
                              }
                            }
                          });
                        }
                        var endLeft;
                        try {
                          endLeft = BigInt.parse("${unlockAt.toString()}") -
                              bestNumber;
                        } catch (e) {
                          endLeft = BigInt.parse("0x${unlockAt.toString()}") -
                              bestNumber;
                        }
                        String amount = Fmt.balance(
                          locks[index]!['balance'].toString(),
                          decimals,
                        );
                        final id = int.parse(locks[index]['referendumId']);
                        return Container(
                            padding: EdgeInsets.only(
                                left: 17, top: 16, right: 16, bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        PluginInfoItem(
                                          title: dic[
                                              'democracy.referendum.number'],
                                          content: "#$id",
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          contentCrossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          titleStyle: Theme.of(context)
                                              .textTheme
                                              .headline5
                                              ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline3
                                              ?.copyWith(
                                                  color: Colors.white,
                                                  fontSize: UI.getTextSize(
                                                      22, context),
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        PluginInfoItem(
                                          title: dic['v3.referendaState'],
                                          content: (widget.plugin.store!.gov
                                                      .referendumStatus[id] ??
                                                  '--')
                                              .toString()
                                              .toUpperCase(),
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          contentCrossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          titleStyle: Theme.of(context)
                                              .textTheme
                                              .headline5
                                              ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline3
                                              ?.copyWith(
                                                  color: Colors.white,
                                                  fontSize: UI.getTextSize(
                                                      22, context),
                                                  fontWeight: FontWeight.bold),
                                        )
                                      ],
                                    ),
                                    InfoItemRow(
                                        dic['democracy.referendum.balance']!,
                                        '$amount $symbol',
                                        labelStyle: style,
                                        contentStyle: style),
                                    InfoItemRow(
                                        dic['democracy.referendum.period']!,
                                        endLeft.toInt() <= 0
                                            ? dic['v3.end']
                                            : '${Fmt.blockToTime(endLeft.toInt(), blockDuration)}',
                                        labelStyle: style,
                                        contentStyle: style),
                                  ],
                                )),
                                Container(width: 74)
                              ],
                            ));
                      },
                      pagination: SwiperPagination(
                          alignment: Alignment.topRight,
                          margin: EdgeInsets.only(top: 24, right: 16),
                          builder: SwiperCustomPagination(builder:
                              (BuildContext context,
                                  SwiperPluginConfig config) {
                            return CustomP(
                                config.activeIndex, config.itemCount);
                          })),
                    )),
                Visibility(
                    visible: redeemable > 0,
                    child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                            padding: EdgeInsets.only(
                                left: 17, top: 16, right: 16, bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                    child: InfoItemRow(dic['v3.canClear']!,
                                        '${Fmt.priceFloor(redeemable, lengthMax: 4)} $symbol',
                                        labelStyle: style,
                                        contentStyle: style)),
                                Container(
                                    width: 74,
                                    height: double.infinity,
                                    padding: EdgeInsets.only(left: 15),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        PluginButton(
                                          height: 30,
                                          title: dic[
                                              'democracy.referendum.clear']!,
                                          onPressed: () {
                                            _onUnlock(unLockIds);
                                          },
                                        )
                                      ],
                                    ))
                              ],
                            ))))
              ],
            ))
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dic = I18n.of(context)!.getDic(i18n_full_dic_karura, 'gov')!;
    return PluginScaffold(
      appBar: PluginAppBar(
        title: Text(I18n.of(context)!
            .getDic(i18n_full_dic_karura, 'common')!['governance']!),
        actions: [PluginAccountInfoAction(widget.keyring)],
      ),
      body: Observer(builder: (_) {
        final list = _tabIndex == 0
            ? widget.plugin.store!.gov.referendums
            : _tabIndex == 1
                ? widget.plugin.store!.gov.proposals
                : widget.plugin.store!.gov.external != null
                    ? [widget.plugin.store!.gov.external]
                    : [];
        final decimals = widget.plugin.networkState.tokenDecimals![0];
        final symbol = widget.plugin.networkState.tokenSymbol![0];
        return RefreshIndicator(
            color: Colors.black,
            backgroundColor: Colors.white,
            key: _refreshKey,
            onRefresh: _freshData,
            child: ListView.builder(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: 16),
              itemCount: 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return buildHeaderView(_locks);
                }
                return Padding(
                    padding: EdgeInsets.only(left: 16, right: 16, top: 20),
                    child: StickyHeader(
                        header: Container(
                            color: Colors.transparent,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PluginTabCard(
                                  [
                                    "${dic['referenda']}",
                                    "${dic['democracy.proposal']}",
                                    "${dic['v3.externals']}"
                                  ],
                                  (index) {
                                    setState(() {
                                      _tabIndex = index;
                                    });
                                  },
                                  _tabIndex,
                                  margin: EdgeInsets.zero,
                                ),
                                ConnectionChecker(widget.plugin,
                                    onConnected: _freshData)
                              ],
                            )),
                        content: list?.length == 0
                            ? Container(
                                padding: EdgeInsets.all(16),
                                margin: EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(8),
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                  color: PluginColorsDark.cardColor,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  I18n.of(context)!.getDic(i18n_full_dic_ui,
                                      'common')!['list.empty']!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headline4
                                      ?.copyWith(color: Colors.white),
                                ))
                            : ListView.builder(
                                itemCount: list?.length ?? 0,
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  if (_tabIndex == 0) {
                                    final info = list![index] as ReferendumInfo;
                                    bool isLock = false;
                                    if (_locks.length > 0) {
                                      _locks.forEach((element) {
                                        if (BigInt.parse(
                                                element['referendumId']) ==
                                            info.index) {
                                          isLock = true;
                                        }
                                      });
                                    }
                                    return ReferendumPanel(
                                      data: info,
                                      isLock: isLock,
                                      bestNumber:
                                          widget.plugin.store!.gov.bestNumber,
                                      symbol: symbol,
                                      decimals: decimals,
                                      blockDuration: widget
                                          .plugin.store!.earn.blockDuration,
                                      onCancelVote: _submitCancelVote,
                                      links: Visibility(
                                        visible: _links[
                                                'referendum===${info.index.toString()}'] !=
                                            null,
                                        child: GovExternalLinks(_links[
                                                'referendum===${info.index.toString()}'] ??
                                            []),
                                      ),
                                      onRefresh: () {
                                        _refreshKey.currentState!.show();
                                      },
                                    );
                                  } else if (_tabIndex == 1) {
                                    final info =
                                        list![index] as ProposalInfoData;
                                    return ProposalPanel(
                                      widget.plugin,
                                      widget.plugin.store!.gov.proposals[index],
                                      Visibility(
                                        visible: _links[
                                                'proposal===${BigInt.parse(info.index).toString()}'] !=
                                            null,
                                        child: GovExternalLinks(_links[
                                                'proposal===${BigInt.parse(info.index).toString()}'] ??
                                            []),
                                      ),
                                      widget.keyring,
                                      onSecondsAction: (p0) => _onSecondsTx(p0),
                                    );
                                  } else {
                                    final info =
                                        list![index] as ProposalInfoData;
                                    return Container(
                                      padding: EdgeInsets.all(16),
                                      margin: EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.only(
                                          topRight: Radius.circular(8),
                                          bottomLeft: Radius.circular(8),
                                          bottomRight: Radius.circular(8),
                                        ),
                                        color: PluginColorsDark.cardColor,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            info.image?.proposal == null
                                                ? ""
                                                : info.image!.proposal!.meta!
                                                    .documentation!
                                                    .trim(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .headline5
                                                ?.copyWith(
                                                    fontSize: UI.getTextSize(
                                                        12, context),
                                                    color: Colors.white),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.only(top: 8),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(dic['treasury.proposer']!,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headline5
                                                        ?.copyWith(
                                                            fontSize:
                                                                UI.getTextSize(
                                                                    12,
                                                                    context),
                                                            color:
                                                                Colors.white)),
                                                Row(
                                                  children: [
                                                    AddressIcon(
                                                      info.proposer,
                                                      svg: widget
                                                              .plugin
                                                              .store!
                                                              .accounts
                                                              .addressIconsMap[
                                                          info.proposer],
                                                      size: 14,
                                                    ),
                                                    Padding(
                                                        padding: EdgeInsets.only(
                                                            left: 5),
                                                        child: UI.accountDisplayName(
                                                            info.proposer,
                                                            widget
                                                                    .plugin
                                                                    .store!
                                                                    .accounts
                                                                    .addressIndexMap[
                                                                info.proposer],
                                                            style: Theme.of(context)
                                                                .textTheme
                                                                .headline5
                                                                ?.copyWith(
                                                                    fontSize: UI.getTextSize(
                                                                        12, context),
                                                                    color: Colors
                                                                        .white),
                                                            expand: false))
                                                  ],
                                                )
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: InfoItemRow(
                                              dic['v3.locked']!,
                                              '${Fmt.balance(
                                                info.image!.balance.toString(),
                                                decimals,
                                              )} $symbol',
                                              labelStyle: Theme.of(context)
                                                  .textTheme
                                                  .headline5
                                                  ?.copyWith(
                                                      fontSize: UI.getTextSize(
                                                          12, context),
                                                      color: Colors.white),
                                              contentStyle: Theme.of(context)
                                                  .textTheme
                                                  .headline5
                                                  ?.copyWith(
                                                      fontSize: UI.getTextSize(
                                                          12, context),
                                                      color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                })));
              },
            ));
      }),
    );
  }
}

class CustomP extends StatelessWidget {
  var _currentIndex;
  var _count;
  CustomP(this._currentIndex, this._count);
  @override
  Widget build(BuildContext context) {
    return Container(
        height: 8,
        child: _count == 1
            ? Container()
            : ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                separatorBuilder: (context, index) => Container(
                  width: 6,
                ),
                scrollDirection: Axis.horizontal,
                itemBuilder: (BuildContext context, int index) {
                  return Container(
                    height: 8,
                    width: _currentIndex == index ? 15 : 8,
                    decoration: BoxDecoration(
                        color: _currentIndex == index
                            ? PluginColorsDark.primary
                            : PluginColorsDark.headline1,
                        borderRadius: BorderRadius.circular(4)),
                  );
                },
                itemCount: _count,
              ));
  }
}
