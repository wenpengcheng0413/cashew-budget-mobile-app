import 'dart:io';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/exportCSV.dart' show cleanFileNameString;
import 'package:budget/pages/addBudgetPage.dart' show WalletChipSelector;
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/statusBox.dart';
import 'package:budget/widgets/util/saveFile.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:provider/provider.dart';

Future saveExcel({
  required BuildContext boxContext,
  required List<int> dataStore,
  required String fileName,
}) async {
  return await saveFile(
    boxContext: boxContext,
    dataStore: dataStore,
    dataString: null,
    fileName: fileName,
    successMessage: "excel-saved-success".tr(),
    errorMessage: "error-exporting".tr(),
  );
}

class ExportExcel extends StatelessWidget {
  const ExportExcel({super.key});

  Future exportExcel({
    required BuildContext boxContext,
    required DateTimeRange? dateTimeRange,
    required List<String>? selectedWalletPks,
  }) async {
    await openLoadingPopupTryCatch(() async {
      List<TransactionWithCategory> transactions = await database
          .getAllTransactionsWithCategoryWalletBudgetObjectiveSubCategory(
        (tbl) =>
            database.onlyShowBasedOnWalletFks(tbl, selectedWalletPks) &
            tbl.paid.equals(true) &
            database.onlyShowBasedOnTimeRange(
              tbl,
              dateTimeRange?.start,
              dateTimeRange?.end,
              null,
            ),
      );

      if (transactions.isEmpty) {
        openSnackbar(SnackbarMessage(
          title: "no-transactions-within-time-range".tr().capitalizeFirstofEach,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.warning_outlined
              : Icons.warning_rounded,
        ));
        return;
      }

      var excel = excel_lib.Excel.createExcel();

      // Sheet 1: Transaction Details
      var sheet1 = excel['Transaction Details'];
      _buildTransactionSheet(sheet1, transactions);

      // Sheet 2: Category Summary
      var sheet2 = excel['Category Summary'];
      _buildCategorySummarySheet(sheet2, transactions);

      // Sheet 3: Monthly Summary
      var sheet3 = excel['Monthly Summary'];
      _buildMonthlySummarySheet(sheet3, transactions);

      List<int>? fileBytes = excel.encode();

      String fileName;
      if (dateTimeRange != null) {
        fileName = "cashew-${DateTime.now().millisecondsSinceEpoch}-"
            "${dateTimeRange.start.year}-${dateTimeRange.start.month}-${dateTimeRange.start.day}"
            "-to-${dateTimeRange.end.year}-${dateTimeRange.end.month}-${dateTimeRange.end.day}.xlsx";
      } else {
        fileName =
            "cashew-${cleanFileNameString(DateTime.now().toString())}.xlsx";
      }

      if (fileBytes != null) {
        await saveExcel(
          boxContext: boxContext,
          dataStore: fileBytes,
          fileName: fileName,
        );
      }
    });
  }

  void _buildTransactionSheet(
      excel_lib.Sheet sheet, List<TransactionWithCategory> transactions) {
    // Header row with styling
    List<String> headers = [
      "account",
      "amount",
      "currency",
      "title",
      "note",
      "date",
      "income",
      "category name",
      "subcategory name",
      "budget",
      "objective",
    ];

    for (int col = 0; col < headers.length; col++) {
      var cell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = excel_lib.TextCellValue(headers[col].tr());
      // Bold header
      cell.cellStyle = excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#4A90D9'),
        fontColorHex: excel_lib.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: excel_lib.HorizontalAlign.Center,
      );
    }

    for (int row = 0; row < transactions.length; row++) {
      var t = transactions[row];
      List<String> values = [
        t.wallet?.name ?? "",
        t.transaction.amount.toString(),
        (t.wallet?.currency ?? "").allCaps,
        t.transaction.name,
        t.transaction.note,
        t.transaction.dateCreated.toString(),
        t.transaction.income.toString(),
        t.category.name,
        t.subCategory?.name ?? "",
        t.budget?.name ?? "",
        t.objective?.name ?? "",
      ];

      for (int col = 0; col < values.length; col++) {
        var cell = sheet.cell(
          excel_lib.CellIndex.indexByColumnRow(
              columnIndex: col, rowIndex: row + 1),
        );
        cell.value = excel_lib.TextCellValue(values[col]);
      }
    }
  }

  void _buildCategorySummarySheet(
      excel_lib.Sheet sheet, List<TransactionWithCategory> transactions) {
    // Aggregate by category
    Map<String, double> categoryTotals = {};
    Map<String, int> categoryCounts = {};

    for (var t in transactions) {
      String catName = t.subCategory?.name ?? t.category.name;
      categoryTotals[catName] =
          (categoryTotals[catName] ?? 0) + t.transaction.amount;
      categoryCounts[catName] = (categoryCounts[catName] ?? 0) + 1;
    }

    var sorted = categoryTotals.entries.toList()
      ..sort((a, b) => a.value.abs().compareTo(b.value.abs()));

    // Headers
    List<String> headers = ["Category", "Total", "Transaction Count", "Type"];
    for (int col = 0; col < headers.length; col++) {
      var cell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = excel_lib.TextCellValue(headers[col]);
      cell.cellStyle = excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#4A90D9'),
        fontColorHex: excel_lib.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: excel_lib.HorizontalAlign.Center,
      );
    }

    for (int i = 0; i < sorted.length; i++) {
      var entry = sorted[i];
      double total = entry.value;
      String type = total > 0 ? "income".tr() : "expense".tr();

      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: i + 1))
          .value = excel_lib.TextCellValue(entry.key);
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1, rowIndex: i + 1))
          .value = excel_lib.DoubleCellValue(total);
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 2, rowIndex: i + 1))
          .value = excel_lib.IntCellValue(categoryCounts[entry.key] ?? 0);
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3, rowIndex: i + 1))
          .value = excel_lib.TextCellValue(type);
    }
  }

  void _buildMonthlySummarySheet(
      excel_lib.Sheet sheet, List<TransactionWithCategory> transactions) {
    // Aggregate by month
    Map<String, Map<String, double>> monthlyData = {}; // month -> {income, expense}

    for (var t in transactions) {
      String monthKey =
          "${t.transaction.dateCreated.year}-${t.transaction.dateCreated.month.toString().padLeft(2, '0')}";
      monthlyData.putIfAbsent(monthKey, () => {"income": 0, "expense": 0});
      if (t.transaction.income) {
        monthlyData[monthKey]!["income"] =
            (monthlyData[monthKey]!["income"] ?? 0) + t.transaction.amount;
      } else {
        monthlyData[monthKey]!["expense"] =
            (monthlyData[monthKey]!["expense"] ?? 0) + t.transaction.amount.abs();
      }
    }

    var sortedMonths = monthlyData.keys.toList()..sort();

    List<String> headers = ["Month", "Income", "Expense", "Net"];
    for (int col = 0; col < headers.length; col++) {
      var cell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = excel_lib.TextCellValue(headers[col]);
      cell.cellStyle = excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#4A90D9'),
        fontColorHex: excel_lib.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: excel_lib.HorizontalAlign.Center,
      );
    }

    for (int i = 0; i < sortedMonths.length; i++) {
      String month = sortedMonths[i];
      double income = monthlyData[month]!["income"] ?? 0;
      double expense = monthlyData[month]!["expense"] ?? 0;
      double net = income - expense;

      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: i + 1))
          .value = excel_lib.TextCellValue(month);
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1, rowIndex: i + 1))
          .value = excel_lib.DoubleCellValue(income);
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 2, rowIndex: i + 1))
          .value = excel_lib.DoubleCellValue(expense);
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3, rowIndex: i + 1))
          .value = excel_lib.DoubleCellValue(net);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (boxContext) {
      return SettingsContainer(
        onTap: () async {
          await openBottomSheet(
            context,
            PopupFramework(
              title: "export-excel".tr(),
              hasPadding: false,
              child: ExportExcelPopup(
                exportExcel: exportExcel,
                boxContext: boxContext,
              ),
            ),
          );
        },
        title: "export-excel".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.table_chart_outlined
            : Icons.table_chart_rounded,
      );
    });
  }
}

class ExportExcelPopup extends StatefulWidget {
  const ExportExcelPopup(
      {required this.exportExcel, required this.boxContext, super.key});
  final Function({
    required BuildContext boxContext,
    required DateTimeRange? dateTimeRange,
    required List<String>? selectedWalletPks,
  }) exportExcel;
  final BuildContext boxContext;

  @override
  State<ExportExcelPopup> createState() => _ExportExcelPopupState();
}

class _ExportExcelPopupState extends State<ExportExcelPopup> {
  List<String>? selectedWallets;

  @override
  void initState() {
    selectedWallets =
        sharedPreferences.getStringList("exportExcelWalletList");
    if (selectedWallets?.isEmpty == true) selectedWallets = null;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WalletChipSelector(
          expand:
              Provider.of<AllWallets>(context, listen: false).list.length > 1,
          onSelected: (selected) {
            selectedWallets = selected;
            sharedPreferences.setStringList(
                "exportExcelWalletList", selected ?? []);
          },
          initiallySelectedWalletFks: selectedWallets,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButtonStacked(
                  text: "all-time".tr().capitalizeFirstofEach,
                  iconData: appStateSettings["outlinedIcons"]
                      ? Icons.calendar_month_outlined
                      : Icons.calendar_month_rounded,
                  onTap: () async {
                    popRoute(context);
                    await widget.exportExcel(
                      boxContext: widget.boxContext,
                      dateTimeRange: null,
                      selectedWalletPks: selectedWallets,
                    );
                  },
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: OutlinedButtonStacked(
                  text: "date-range".tr().capitalizeFirstofEach,
                  iconData: appStateSettings["outlinedIcons"]
                      ? Icons.date_range_outlined
                      : Icons.date_range_rounded,
                  onTap: () async {
                    popRoute(context);
                    DateTimeRangeOrAllTime? dateRange =
                        await showCustomDateRangePicker(
                      context,
                      null,
                      initialEntryMode: DatePickerEntryMode.calendarOnly,
                      allTimeButton: false,
                    );
                    if (dateRange.dateTimeRange == null) {
                      openSnackbar(
                        SnackbarMessage(
                          icon: appStateSettings["outlinedIcons"]
                              ? Icons.event_busy_outlined
                              : Icons.event_busy_rounded,
                          title: "date-not-selected".tr(),
                        ),
                      );
                    } else {
                      await widget.exportExcel(
                        boxContext: widget.boxContext,
                        dateTimeRange: dateRange.dateTimeRange,
                        selectedWalletPks: selectedWallets,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
