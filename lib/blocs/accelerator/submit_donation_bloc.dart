import 'package:zenon_syrius_wallet_flutter/blocs/accelerator/accelerator_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/base_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class SubmitDonationBloc extends BaseBloc<AccountBlockTemplate?> {
  Future<void> submitDonation(num znnAmount, num qsrAmount) async {
    try {
      addEvent(null);
      if (znnAmount > 0) {
        await _sendDonationBlock(zenon!.embedded.accelerator.donate(
          znnAmount.extractDecimals(znnDecimals),
          kZnnCoin.tokenStandard,
        ));
      }
      if (qsrAmount > 0) {
        await _sendDonationBlock(zenon!.embedded.accelerator.donate(
          qsrAmount.extractDecimals(qsrDecimals),
          kQsrCoin.tokenStandard,
        ));
      }
    } catch (e) {
      addError(e);
    }
  }

  Future<void> _sendDonationBlock(
      AccountBlockTemplate transactionParams) async {
    await AccountBlockUtils.createAccountBlock(
      transactionParams,
      'donate for accelerator',
    ).then(
      (block) {
        sl.get<AcceleratorBalanceBloc>().getAcceleratorBalance();
        addEvent(block);
      },
    ).onError(
      (error, stackTrace) {
        addError(error.toString());
      },
    );
  }
}
