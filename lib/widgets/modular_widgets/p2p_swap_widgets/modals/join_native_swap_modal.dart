import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:stacked/stacked.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/dashboard/balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/htlc/create_htlc_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/initial_htlc_for_swap_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/clipboard_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/htlc_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/instruction_button.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/error_widget.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/exchange_rate_widget.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/important_text_container.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_field/amount_input_field.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_field/disabled_address_field.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_field/input_field.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_field/labeled_input_container.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/loading_widget.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/base_modal.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class JoinNativeSwapModal extends StatefulWidget {
  final Function(String) onJoinedSwap;

  const JoinNativeSwapModal({
    required this.onJoinedSwap,
    Key? key,
  }) : super(key: key);

  @override
  State<JoinNativeSwapModal> createState() => _JoinNativeSwapModalState();
}

class _JoinNativeSwapModalState extends State<JoinNativeSwapModal> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _depositIdController = TextEditingController();

  late String _selfAddress;

  HtlcInfo? _initialHltc;
  String? _initialHtlcError;
  int? _safeExpirationTime;
  StreamSubscription? _safeExpirationSubscription;

  Token _selectedToken = kZnnCoin;
  bool _isAmountValid = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    sl.get<BalanceBloc>().getBalanceForAllAddresses();
    _safeExpirationSubscription =
        Stream.periodic(const Duration(seconds: 5)).listen((_) {
      if (_initialHltc != null) {
        _safeExpirationTime =
            _calculateSafeExpirationTime(_initialHltc!.expirationTime);
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _safeExpirationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BaseModal(
      title: 'Join swap',
      child: _initialHltc == null
          ? _getSearchView()
          : FutureBuilder<Token?>(
              future:
                  zenon!.embedded.token.getByZts(_initialHltc!.tokenStandard),
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return SyriusErrorWidget(snapshot.error!);
                } else if (snapshot.hasData) {
                  return _getContent(snapshot.data!);
                }
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SyriusLoadingWidget(),
                );
              },
            ),
    );
  }

  Widget _getSearchView() {
    return Column(
      children: [
        const SizedBox(
          height: 20.0,
        ),
        Form(
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: InputField(
            onChanged: (value) {
              setState(() {});
            },
            validator: (value) => InputValidators.checkHash(value),
            controller: _depositIdController,
            suffixIcon: RawMaterialButton(
              child: const Icon(
                Icons.content_paste,
                color: AppColors.darkHintTextColor,
                size: 15.0,
              ),
              shape: const CircleBorder(),
              onPressed: () => ClipboardUtils.pasteToClipboard(
                context,
                (String value) {
                  _depositIdController.text = value;
                  setState(() {});
                },
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              maxWidth: 45.0,
              maxHeight: 20.0,
            ),
            hintText: 'Deposit ID provided by the counterparty',
            contentLeftPadding: 10.0,
          ),
        ),
        const SizedBox(
          height: 25.0,
        ),
        Visibility(
          visible: _initialHtlcError != null,
          child: Column(
            children: [
              ImportantTextContainer(
                text: _initialHtlcError ?? '',
                showBorder: true,
              ),
              const SizedBox(
                height: 25.0,
              ),
            ],
          ),
        ),
        _getHtlcViewModel(),
      ],
    );
  }

  _getHtlcViewModel() {
    return ViewModelBuilder<InitialHtlcForSwapBloc>.reactive(
      onModelReady: (model) {
        model.stream.listen(
          (event) async {
            if (event is HtlcInfo) {
              _initialHltc = event;
              _isLoading = false;
              _addressController.text = event.hashLocked.toString();
              _selfAddress = event.hashLocked.toString();
              _safeExpirationTime =
                  _calculateSafeExpirationTime(event.expirationTime);
              _initialHtlcError = null;
              setState(() {});
            }
          },
          onError: (error) {
            setState(() {
              _initialHtlcError = error.toString();
              _isLoading = false;
            });
          },
        );
      },
      builder: (_, model, __) => _getContinueButton(model),
      viewModelBuilder: () => InitialHtlcForSwapBloc(),
    );
  }

  Widget _getContinueButton(InitialHtlcForSwapBloc model) {
    return InstructionButton(
      text: 'Continue',
      loadingText: 'Searching',
      instructionText: 'Input the deposit ID',
      isEnabled: _isHashValid(),
      isLoading: _isLoading,
      onPressed: () => _onContinueButtonPressed(model),
    );
  }

  void _onContinueButtonPressed(InitialHtlcForSwapBloc model) async {
    setState(() {
      _isLoading = true;
    });
    model.getInitialHtlc(Hash.parse(_depositIdController.text));
  }

  Widget _getContent(Token tokenToReceive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20.0),
        Row(
          children: [
            Expanded(
              child: LabeledInputContainer(
                labelText: 'Your address',
                helpText: 'You will receive the swapped funds to this address.',
                inputWidget: DisabledAddressField(
                  _addressController,
                  contentLeftPadding: 10.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20.0),
        Divider(color: Colors.white.withOpacity(0.1)),
        const SizedBox(height: 20.0),
        LabeledInputContainer(
          labelText: 'You are sending',
          inputWidget: Flexible(
            child: StreamBuilder<Map<String, AccountInfo>?>(
              stream: sl.get<BalanceBloc>().stream,
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return SyriusErrorWidget(snapshot.error!);
                }
                if (snapshot.connectionState == ConnectionState.active) {
                  if (snapshot.hasData) {
                    return AmountInputField(
                      controller: _amountController,
                      accountInfo: (snapshot.data![_selfAddress]!),
                      valuePadding: 10.0,
                      textColor: Theme.of(context).colorScheme.inverseSurface,
                      initialToken: _selectedToken,
                      hintText: '0.0',
                      onChanged: (token, isValid) {
                        setState(() {
                          _selectedToken = token;
                          _isAmountValid = isValid;
                        });
                      },
                    );
                  } else {
                    return const SyriusLoadingWidget();
                  }
                } else {
                  return const SyriusLoadingWidget();
                }
              },
            ),
          ),
        ),
        kVerticalSpacing,
        const Icon(
          AntDesign.arrowdown,
          color: Colors.white,
          size: 20,
        ),
        kVerticalSpacing,
        HtlcCard.fromHtlcInfo(
          title: 'You are receiving',
          htlc: _initialHltc!,
          token: tokenToReceive,
        ),
        const SizedBox(height: 20.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Exchange Rate',
                style:
                    TextStyle(fontSize: 14.0, color: AppColors.subtitleColor),
              ),
              _getExchangeRateWidget(tokenToReceive),
            ],
          ),
        ),
        const SizedBox(height: 20.0),
        Divider(color: Colors.white.withOpacity(0.1)),
        const SizedBox(height: 25.0),
        _safeExpirationTime != null
            ? _getJoinSwapViewModel(tokenToReceive)
            : const ImportantTextContainer(
                text:
                    'Cannot join swap. The swap will expire too soon for a safe swap.',
                showBorder: true,
              )
      ],
    );
  }

  _getJoinSwapViewModel(Token tokenToReceive) {
    return ViewModelBuilder<CreateHtlcBloc>.reactive(
      onModelReady: (model) {
        model.stream.listen(
          (event) async {
            if (event is AccountBlockTemplate) {
              final data = AccountBlockUtils.getDecodedBlockData(
                  Definitions.htlc, event.data)!;
              await htlcSwapsService!.storeSwap(HtlcSwap(
                id: _initialHltc!.id.toString(),
                type: P2pSwapType.native,
                direction: P2pSwapDirection.incoming,
                selfAddress: _selfAddress,
                counterpartyAddress: _initialHltc!.timeLocked.toString(),
                state: P2pSwapState.active,
                startTime:
                    (DateTime.now().millisecondsSinceEpoch / 1000).round(),
                initialHtlcExpirationTime: _initialHltc!.expirationTime,
                counterHtlcExpirationTime:
                    data.params['expirationTime'].toInt(),
                fromAmount: event.amount,
                fromTokenStandard: _selectedToken.tokenStandard.toString(),
                fromDecimals: _selectedToken.decimals,
                fromSymbol: _selectedToken.symbol,
                fromChain: P2pSwapChain.nom,
                toChain: P2pSwapChain.nom,
                toAmount: _initialHltc!.amount,
                toTokenStandard: tokenToReceive.tokenStandard.toString(),
                toDecimals: tokenToReceive.decimals,
                toSymbol: tokenToReceive.symbol,
                hashLock: FormatUtils.encodeHexString(_initialHltc!.hashLock),
                initialHtlcId: _initialHltc!.id.toString(),
                counterHtlcId: event.hash.toString(),
                hashType: _initialHltc!.hashType,
              ));
              widget.onJoinedSwap.call(_initialHltc!.id.toString());
            }
          },
          onError: (error) {
            setState(() {
              _isLoading = false;
            });
          },
        );
      },
      builder: (_, model, __) => _getJoinSwapButton(model),
      viewModelBuilder: () => CreateHtlcBloc(),
    );
  }

  Widget _getJoinSwapButton(CreateHtlcBloc model) {
    return InstructionButton(
      text: 'Join swap',
      instructionText: 'Input an amount to send',
      loadingText: 'Sending transaction',
      isEnabled: _isInputValid(),
      isLoading: _isLoading,
      onPressed: () => _onJoinButtonPressed(model),
    );
  }

  void _onJoinButtonPressed(CreateHtlcBloc model) async {
    setState(() {
      _isLoading = true;
    });

    model.createHtlc(
      timeLocked: Address.parse(_selfAddress),
      token: _selectedToken,
      amount: _amountController.text,
      hashLocked: _initialHltc!.timeLocked,
      expirationTime: _safeExpirationTime!,
      hashType: _initialHltc!.hashType,
      keyMaxSize: _initialHltc!.keyMaxSize,
      hashLock: _initialHltc!.hashLock,
    );
  }

  int? _calculateSafeExpirationTime(int initialHtlcExpiration) {
    const minimumSafeTime = Duration(hours: 1);
    final now = (DateTime.now().millisecondsSinceEpoch / 1000).round();
    final remaining = Duration(seconds: initialHtlcExpiration - now);
    final safeTime = remaining ~/ 2;
    return safeTime >= minimumSafeTime ? now + safeTime.inSeconds : null;
  }

  Widget _getExchangeRateWidget(Token tokenToReceive) {
    final fromAmount =
        _amountController.text.isNotEmpty ? _amountController.text.toNum() : 0;
    return ExchangeRateWidget(
        fromAmount: fromAmount.extractDecimals(_selectedToken.decimals),
        fromDecimals: _selectedToken.decimals,
        fromSymbol: _selectedToken.symbol,
        toAmount: _initialHltc!.amount,
        toDecimals: tokenToReceive.decimals,
        toSymbol: tokenToReceive.symbol);
  }

  bool _isInputValid() => _isAmountValid;

  bool _isHashValid() =>
      InputValidators.checkHash(_depositIdController.text) == null;
}
