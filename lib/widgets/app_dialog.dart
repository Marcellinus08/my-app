import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Standard dialog styling and builder for Teman Arah
class AppDialogStyle {
  // Standard padding
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(20, 16, 20, 0);
  static const EdgeInsets actionPadding = EdgeInsets.fromLTRB(20, 20, 20, 20);
  static const EdgeInsets titlePadding = EdgeInsets.fromLTRB(20, 20, 20, 0);

  // Inset padding
  static const EdgeInsets insetPadding = EdgeInsets.symmetric(horizontal: 20);

  // Border radius
  static const double borderRadius = 16;

  // Border color
  static const Color borderColor = Color(0xFFE2E8F0);

  // Barrier color - subtle overlay
  static const Color barrierColor = Color.fromRGBO(15, 23, 42, 0.4);
}

/// Standard dialog builder for confirmation dialogs
Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  String? description,
  String? cancelText,
  String? confirmText,
  IconData? icon,
  Color? iconColor,
  Color? confirmButtonColor,
  bool isDangerous = false,
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: AppDialogStyle.barrierColor,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: AppDialogStyle.insetPadding,
      titlePadding: AppDialogStyle.titlePadding,
      contentPadding: AppDialogStyle.contentPadding,
      actionsPadding: AppDialogStyle.actionPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDialogStyle.borderRadius),
        side: const BorderSide(color: AppDialogStyle.borderColor, width: 1),
      ),
      title: icon != null
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        (iconColor ??
                                (isDangerous
                                    ? AppColors.error
                                    : AppColors.primary))
                            .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color:
                        iconColor ??
                        (isDangerous ? AppColors.error : AppColors.primary),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            )
          : Text(
              title,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
      content: description != null
          ? Text(
              description,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            )
          : null,
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  cancelText ?? 'Batal',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor:
                      confirmButtonColor ??
                      (isDangerous ? AppColors.error : AppColors.primary),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmText ?? 'Konfirmasi'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Builder for info/alert dialogs
void showAppInfoDialog({
  required BuildContext context,
  required String title,
  String? description,
  IconData? icon,
  Color? iconColor,
  String? buttonText,
  VoidCallback? onClose,
}) {
  showDialog(
    context: context,
    barrierColor: AppDialogStyle.barrierColor,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: AppDialogStyle.insetPadding,
      titlePadding: AppDialogStyle.titlePadding,
      contentPadding: AppDialogStyle.contentPadding,
      actionsPadding: AppDialogStyle.actionPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDialogStyle.borderRadius),
        side: const BorderSide(color: AppDialogStyle.borderColor, width: 1),
      ),
      title: icon != null
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppColors.info).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor ?? AppColors.info,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            )
          : Text(
              title,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
      content: description != null
          ? Text(
              description,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            )
          : null,
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onClose?.call();
            },
            child: Text(buttonText ?? 'Tutup'),
          ),
        ),
      ],
    ),
  );
}
