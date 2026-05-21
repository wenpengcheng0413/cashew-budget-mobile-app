import 'dart:io';
import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/animatedExpanded.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/dropdownSelect.dart';
import 'package:budget/widgets/importCSV.dart' show ImportingTransactionAndTitle, CustomDateFormatInput, tryDateFormatting, tryToParseCustomDateFormat, saveSampleCSV;
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/tableEntry.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/progressBar.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/struct/commonDateFormats.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:provider/provider.dart';

class ImportExcel extends StatefulWidget {
  const ImportExcel({Key? key}) : super(key: key);

  @override
  State<ImportExcel> createState() => _ImportExcelState();
}

class _ImportExcelState extends State<ImportExcel> {
  int _getHeaderIndex(List<String> headers, String header) {
    int index = 0;
    for (String headerEntry in headers) {
      if (header == headerEntry) {
        return index;
      }
      index++;
    }
    return -1;
  }

  Future<List<List<String>>?> _getDataFromExcelFile() async {
    return await openLoadingPopupTryCatch(() async {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: ['xlsx', 'xls'],
        type: FileType.custom,
      );

      if (result != null) {
        List<int> fileBytes;
        if (kIsWeb) {
          fileBytes = result.files.single.bytes!;
        } else {
          File file = File(result.files.single.path ?? "");
          fileBytes = await file.readAsBytes();
        }

        var excel = excel_lib.Excel.decodeBytes(fileBytes);
        var sheet = excel.tables.keys.first;
        var table = excel.tables[sheet]!;

        List<List<String>> rows = [];
        for (var row in table.rows) {
          rows.add(row.map((cell) => cell?.value?.toString() ?? "").toList());
        }
        return rows;
      } else {
        throw "no-file-selected".tr();
      }
    }, onError: (e) {
      print("Error opening Excel: " + e.toString());
      openPopup(
        context,
        title: "excel-error".tr(),
        description: "consider-csv-template".tr() + "\n" + e.toString(),
        onCancelWithBoxContext: (BuildContext boxContext) async {
          await saveSampleCSV(boxContext: boxContext);
          popRoute(context);
        },
        onCancelLabel: "get-template".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
        onSubmitLabel: "ok".tr(),
        onSubmit: () {
          popRoute(context);
        },
        barrierDismissible: false,
      );
    });
  }

  Future<void> _assignColumnsExcel(List<List<String>> fileContents) async {
    try {
      int maxColumns = fileContents.fold(
          0, (prev, element) => element.length > prev ? element.length : prev);

      fileContents = fileContents
          .map((row) => row + List.filled(maxColumns - row.length, ""))
          .toList();

      fileContents = fileContents
          .where((list) => list.any((element) => element.trim().isNotEmpty))
          .toList();

      int headersIndex =
          _findListIndexWithMultipleNonEmptyStrings(fileContents) ?? 0;
      List<String> headers = fileContents[headersIndex];
      List<String> firstEntry = fileContents[
          _findListIndexWithMultipleNonEmptyStrings(fileContents,
                  afterIndex: headersIndex) ??
              1];

      String dateFormat = "";
      Map<String, Map<String, dynamic>> assignedColumns = {
        "date": {
          "displayName": "date",
          "headerValues": [
            "FormattedDate",
            "date",
            "date created",
            "dateCreated"
          ],
          "required": true,
          "setHeaderValue": "",
          "setHeaderIndex": -1,
        },
        "amount": {
          "displayName": "amount",
          "headerValues": ["amount"],
          "required": true,
          "setHeaderValue": "",
          "setHeaderIndex": -1,
        },
        "category": {
          "displayName": "category",
          "headerValues": ["category", "category name", "categoryName"],
          "required": true,
          "setHeaderValue": "",
          "setHeaderIndex": -1,
        },
        "name": {
          "displayName": "title",
          "headerValues": ["title", "name"],
          "required": false,
          "setHeaderValue": "",
          "setHeaderIndex": -1,
        },
        "note": {
          "displayName": "note",
          "headerValues": ["note"],
          "required": false,
          "setHeaderValue": "",
          "setHeaderIndex": -1,
        },
        "wallet": {
          "displayName": "account",
          "headerValues": ["wallet", "account", "accountName", "account name"],
          "required": true,
          "setHeaderValue": "",
          "setHeaderIndex": -1,
          "canSelectCurrentWallet": true,
        },
      };

      for (dynamic key in assignedColumns.keys) {
        String setHeaderValue = determineInitialValue(
            assignedColumns[key]!["headerValues"],
            headers,
            assignedColumns[key]!["required"],
            assignedColumns[key]!["canSelectCurrentWallet"]);
        assignedColumns[key]!["setHeaderValue"] = setHeaderValue;
        assignedColumns[key]!["setHeaderIndex"] =
            _getHeaderIndex(headers, setHeaderValue);
      }

      final customDateFormatKey = GlobalKey();
      Color containerColor = appStateSettings["materialYou"]
          ? dynamicPastel(
              context,
              Theme.of(context).colorScheme.secondaryContainer,
              amountDark: 0.2,
              amountLight: 0.35,
            )
          : getColor(context, "lightDarkAccentHeavyLight").withOpacity(0.6);

      openBottomSheet(
        context,
        PopupFramework(
          hasPadding: false,
          title: "assign-columns-excel".tr(),
          subtitle: (fileContents.length - 1).toString() +
              " " +
              "transactions-in-the-excel".tr(),
          child: Column(
            children: [
              TableEntry(
                firstEntry: firstEntry,
                headers: headers,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 18, vertical: 15),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 5),
                      child: Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                            vertical: 10, horizontal: 15),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadiusDirectional.circular(10),
                          color: containerColor,
                        ),
                        child: CustomDateFormatInput(
                          key: customDateFormatKey,
                          setDateFormat: (value) {
                            dateFormat = value;
                          },
                          firstDateString: firstEntry[assignedColumns["date"]
                                  ?["setHeaderIndex"]]
                              .toString()
                              .trim(),
                        ),
                      ),
                    ),
                    for (dynamic key in assignedColumns.keys)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 5),
                        child: Container(
                          padding: const EdgeInsetsDirectional.symmetric(
                              vertical: 10, horizontal: 15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadiusDirectional.circular(10),
                            color: containerColor,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  runAlignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    TextFont(
                                      text: assignedColumns[key]!["displayName"]
                                          .toString()
                                          .tr()
                                          .capitalizeFirst,
                                      fontSize: 15,
                                    ),
                                    const SizedBox(width: 10),
                                    DropdownSelect(
                                      compact: true,
                                      initial: assignedColumns[key]![
                                          "setHeaderValue"],
                                      items: assignedColumns[key]![
                                                  "canSelectCurrentWallet"] ==
                                              true
                                          ? ["~Current Wallet~", ...headers]
                                          : assignedColumns[key]!["required"]
                                              ? [
                                                  ...(assignedColumns[key]?[
                                                                  "setHeaderValue"] ==
                                                              ""
                                                          ? [""]
                                                          : []),
                                                  ...headers
                                                ]
                                              : ["~None~", ...headers],
                                      boldedValues: [
                                        "~Current Wallet~",
                                        "~None~"
                                      ],
                                      getLabel: (label) {
                                        if (label == "~Current Wallet~") {
                                          return "~" +
                                              "current-account".tr() +
                                              "~";
                                        } else if (label == "~None~") {
                                          return "~" + "none".tr() + "~";
                                        }
                                        return label;
                                      },
                                      onChanged: (String setHeaderValue) {
                                        assignedColumns[key]![
                                            "setHeaderValue"] = setHeaderValue;
                                        assignedColumns[key]![
                                                "setHeaderIndex"] =
                                            _getHeaderIndex(
                                                headers, setHeaderValue);
                                        if (key == "date") {
                                          (customDateFormatKey.currentState as dynamic)
                                              ?.updateFirstDateString(
                                                  firstEntry[assignedColumns[
                                                              "date"]
                                                          ?["setHeaderIndex"]]
                                                      .toString()
                                                      .trim());
                                        }
                                      },
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      checkInitialValue: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
                child: Button(
                  label: "import".tr(),
                  onTap: () async {
                    try {
                      await _importExcelEntries(
                          assignedColumns, dateFormat, fileContents);
                    } catch (e) {
                      openPopup(
                        context,
                        icon: appStateSettings["outlinedIcons"]
                            ? Icons.warning_outlined
                            : Icons.warning_rounded,
                        title: "excel-error".tr(),
                        description:
                            "consider-csv-template".tr() + "\n" + e.toString(),
                        onSubmit: () => popRoute(context),
                        onSubmitLabel: "ok".tr(),
                        barrierDismissible: false,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      openPopup(
        context,
        title: "excel-error".tr(),
        description: "consider-csv-template".tr() + "\n" + e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
        onSubmitLabel: "ok".tr(),
        onSubmit: () => popRoute(context),
        barrierDismissible: false,
      );
    }
  }

  Future<void> _importExcelEntries(
      Map<String, Map<String, dynamic>> assignedColumns,
      String dateFormat,
      List<List<String>> fileContents) async {
    try {
      for (dynamic key in assignedColumns.keys) {
        if (assignedColumns[key]!["setHeaderValue"] == "") {
          throw "Please make sure you select a parameter for each required field.";
        }
      }
    } catch (e) {
      throw (e.toString());
    }

    popRoute(context);

    int headersIndex =
        _findListIndexWithMultipleNonEmptyStrings(fileContents) ?? 0;
    int firstEntryIndex = _findListIndexWithMultipleNonEmptyStrings(
            fileContents,
            afterIndex: headersIndex) ??
        1;

    openPopupCustom(
      context,
      title: "importing-loading".tr(),
      child: ImportingExcelEntriesPopup(
        dateFormat: dateFormat,
        assignedColumns: assignedColumns,
        fileContents: fileContents,
        next: (numberOfErrors) {
          popRoute(context);
          openPopup(
            context,
            icon: appStateSettings["outlinedIcons"]
                ? Icons.check_circle_outline_outlined
                : Icons.check_circle_outline_rounded,
            title: "done".tr() + "!",
            description: "successfully-imported".tr().capitalizeFirst +
                " " +
                (fileContents.length - firstEntryIndex - numberOfErrors)
                    .toString() +
                " " +
                "transactions".tr().toLowerCase() +
                "." +
                (numberOfErrors > 0
                    ? (" " +
                        "errors".tr().capitalizeFirst +
                        ": " +
                        numberOfErrors.toString() +
                        ".")
                    : ""),
            onSubmitLabel: "ok".tr(),
            onSubmit: () => popRoute(context),
            barrierDismissible: false,
          );
        },
      ),
      barrierDismissible: false,
    );
  }

  String determineInitialValue(List<String> headerValues, List<String> headers,
      bool required, bool? canSelectCurrentWallet) {
    for (String header in headers) {
      if (headerValues.contains(header.toLowerCase()) ||
          headerValues.contains(header) ||
          headerValues.contains(header.toLowerCase().trim())) {
        return header;
      }
    }
    if (canSelectCurrentWallet == true) {
      return "~Current Wallet~";
    }
    if (!required) {
      return "~None~";
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      onTap: () async {
        List<List<String>>? fileContents = await _getDataFromExcelFile();
        if (fileContents != null) {
          _assignColumnsExcel(fileContents);
        }
      },
      title: "import-excel".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.table_chart_outlined
          : Icons.table_chart_rounded,
    );
  }
}

class ImportingExcelEntriesPopup extends StatefulWidget {
  const ImportingExcelEntriesPopup({
    required this.assignedColumns,
    required this.dateFormat,
    required this.fileContents,
    required this.next,
    Key? key,
  }) : super(key: key);

  final Map<String, Map<String, dynamic>> assignedColumns;
  final String dateFormat;
  final List<List<String>> fileContents;
  final Function(int numberOfErrors) next;

  @override
  State<ImportingExcelEntriesPopup> createState() =>
      _ImportingExcelEntriesPopupState();
}

class _ImportingExcelEntriesPopupState
    extends State<ImportingExcelEntriesPopup> {
  double currentPercent = 0;
  int currentEntryIndex = 0;
  int currentFileLength = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _importEntries(
        widget.assignedColumns, widget.dateFormat, widget.fileContents));
  }

  Future<void> _importEntries(Map<String, Map<String, dynamic>> assignedColumns,
      String dateFormat, List<List<String>> fileContents) async {
    List<String> skippedError = [];
    try {
      List<TransactionsCompanion> transactionsInserting = [];
      List<AssociatedTitlesCompanion> titlesInserting = [];

      int headersIndex =
          _findListIndexWithMultipleNonEmptyStrings(fileContents) ?? 0;
      int firstEntryIndex = _findListIndexWithMultipleNonEmptyStrings(
              fileContents,
              afterIndex: headersIndex) ??
          1;

      for (int i = firstEntryIndex; i < fileContents.length; i++) {
        setState(() {
          currentPercent = i / fileContents.length * 100;
          currentEntryIndex = i;
          currentFileLength = fileContents.length;
        });

        List<String> row = fileContents[i];
        List<String>? header = fileContents.firstOrNull;
        int? transactionTypeIndex;
        if (header != null) {
          String searchTerm = "Transaction Type";
          for (int j = 0; j < header.length; j++) {
            if (header[j].toString().trim() == searchTerm.trim()) {
              transactionTypeIndex = j;
              break;
            }
          }
        }

        try {
          var result = await _importEntry(
            assignedColumns,
            dateFormat,
            row,
            i,
            transactionTypeIndex: transactionTypeIndex,
          );

          if (result != null) {
            TransactionsCompanion companion =
                result.transaction.toCompanion(true);
            companion = companion.copyWith(transactionPk: Value.absent());
            transactionsInserting.add(companion);

            if (result.title != null) {
              AssociatedTitlesCompanion titleCompanion =
                  result.title!.toCompanion(true);
              titleCompanion =
                  titleCompanion.copyWith(associatedTitlePk: Value.absent());
              titlesInserting.add(titleCompanion);
            }
          }
        } catch (e) {
          skippedError
              .add("Skipping row #${i.toString()}\n${e.toString()}");
        }
      }

      titlesInserting
          .sort((a, b) => b.dateCreated.value.compareTo(a.dateCreated.value));
      Map<String, AssociatedTitlesCompanion> titlesMap = {};
      for (AssociatedTitlesCompanion item in titlesInserting) {
        titlesMap[item.title.value] = item;
      }
      List<AssociatedTitlesCompanion> filteredList =
          titlesMap.values.toList();

      await database.createBatchTransactionsOnly(transactionsInserting);
      await database.createBatchAssociatedTitlesOnly(filteredList);
      await database.fixOrderAssociatedTitles();

      if (skippedError.isNotEmpty) {
        await openPopup(
          context,
          title: "excel-error".tr(),
          description: "consider-csv-template".tr() +
              "\n" +
              "Skipped importing ${skippedError.length} entries: \n\n${skippedError.take(10).join("\n\n")}",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded,
          onSubmitLabel: "ok".tr(),
          onSubmit: () => popRoute(context),
          barrierDismissible: false,
        );
      }

      widget.next(skippedError.length);
    } catch (e) {
      openPopup(
        context,
        title: "excel-error".tr(),
        description: "consider-csv-template".tr() + "\n" + e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
        onSubmitLabel: "ok".tr(),
        onSubmit: () {
          popRoute(context);
          popRoute(context);
        },
        barrierDismissible: false,
      );
    }
  }

  Future<ImportingTransactionAndTitle?> _importEntry(
      Map<String, Map<String, dynamic>> assignedColumns,
      String dateFormat,
      List<String> row,
      int i,
      {int? transactionTypeIndex}) async {
    String name = "";
    if (assignedColumns["name"]!["setHeaderIndex"] != -1) {
      name = row[assignedColumns["name"]!["setHeaderIndex"]].toString().trim();
    }

    double? amount;
    amount = getAmountFromString(
        (row[assignedColumns["amount"]!["setHeaderIndex"]]).toString().trim());
    if (amount == null) throw ("Unable to parse amount");

    if (transactionTypeIndex != null) {
      if (row[transactionTypeIndex].toString().trim().toLowerCase() ==
          "credit") {
        amount = amount.abs();
      } else if (row[transactionTypeIndex].trim().toLowerCase() == "debit") {
        amount = amount.abs() * -1;
      }
    }

    String note = "";
    if (assignedColumns["note"]!["setHeaderIndex"] != -1) {
      note = row[assignedColumns["note"]!["setHeaderIndex"]].toString().trim();
    }

    String categoryFk = "0";
    TransactionCategory selectedCategory;
    try {
      selectedCategory = await database.getCategoryInstanceGivenName(
          row[assignedColumns["category"]!["setHeaderIndex"]]
              .toString()
              .trim());
    } catch (e) {
      try {
        selectedCategory = await database.getCategoryInstanceGivenNameTrim(
            row[assignedColumns["category"]!["setHeaderIndex"]]
                .toString()
                .trim());
      } catch (e) {
        int numberOfCategories =
            (await database.getTotalCountOfCategories())[0] ?? 0;
        await database.createOrUpdateCategory(
          insert: true,
          TransactionCategory(
            categoryPk: "-1",
            name: row[assignedColumns["category"]!["setHeaderIndex"]]
                .toString()
                .trim(),
            dateCreated: DateTime.now(),
            dateTimeModified: DateTime.now(),
            order: numberOfCategories,
            income: amount > 0,
            iconName: "image.png",
            methodAdded: MethodAdded.csv,
          ),
        );
        selectedCategory = await database.getCategoryInstanceGivenName(
            row[assignedColumns["category"]!["setHeaderIndex"]]
                .toString()
                .trim());
      }
    }
    categoryFk = selectedCategory.categoryPk;

    String walletFk = "0";
    if (assignedColumns["wallet"]!["setHeaderIndex"] == -1 ||
        row[assignedColumns["wallet"]!["setHeaderIndex"]].toString().trim() ==
            "") {
      walletFk = appStateSettings["selectedWalletPk"];
    } else {
      try {
        walletFk = (await database.getWalletInstanceGivenName(
                row[assignedColumns["wallet"]!["setHeaderIndex"]]
                    .toString()
                    .trim()))
            .walletPk;
      } catch (e) {
        try {
          walletFk = (await database.getWalletInstanceGivenNameTrim(
                  row[assignedColumns["wallet"]!["setHeaderIndex"]]
                      .toString()
                      .trim()))
              .walletPk;
        } catch (e) {
          try {
            int numberOfWallets =
                (await database.getTotalCountOfWallets())[0] ?? 0;
            await database.createOrUpdateWallet(
              insert: true,
              Provider.of<AllWallets>(context, listen: false)
                  .indexedByPk[appStateSettings["selectedWalletPk"]]!
                  .copyWith(
                    walletPk: "-1",
                    name: row[assignedColumns["wallet"]!["setHeaderIndex"]]
                        .toString()
                        .trim(),
                    dateCreated: DateTime.now(),
                    dateTimeModified: Value(DateTime.now()),
                    order: numberOfWallets,
                  ),
            );
            walletFk = (await database.getWalletInstanceGivenName(
                    row[assignedColumns["wallet"]!["setHeaderIndex"]]
                        .toString()
                        .trim()))
                .walletPk;
          } catch (e) {
            throw "Wallet not found! Details: ${e.toString()}";
          }
        }
      }
    }

    DateTime dateCreated;
    try {
      dateCreated = DateTime.parse(
          row[assignedColumns["date"]!["setHeaderIndex"]].toString().trim());
      dateCreated = DateTime(
        dateCreated.year,
        dateCreated.month,
        dateCreated.day,
        dateCreated.hour,
        dateCreated.minute,
        dateCreated.second,
      );
    } catch (e) {
      String stringToParse = row[assignedColumns["date"]!["setHeaderIndex"]]
          .toString()
          .replaceAll("  ", " ")
          .trim();
      DateTime? result;
      if (dateFormat == "") {
        for (String commonFormat in getCommonDateFormats()) {
          result = tryDateFormatting(context, commonFormat, stringToParse);
          if (result != null) break;
        }
        if (result == null) {
          throw "Failed to parse date! Details: ${e.toString()}";
        } else {
          dateCreated = result;
        }
      } else {
        dateCreated = tryToParseCustomDateFormat(
          context,
          dateFormat,
          stringToParse,
        );
      }
    }

    bool income = amount > 0;
    String mainCategoryFk =
        selectedCategory.mainCategoryPk ?? selectedCategory.categoryPk;
    String? subCategoryFk = selectedCategory.mainCategoryPk == null
        ? null
        : selectedCategory.categoryPk;

    return ImportingTransactionAndTitle(
      Transaction(
        transactionPk: "-1",
        name: name,
        amount: amount,
        note: note,
        categoryFk: mainCategoryFk,
        subCategoryFk: subCategoryFk,
        walletFk: walletFk,
        dateCreated: dateCreated,
        dateTimeModified: DateTime.now(),
        income: income,
        paid: true,
        skipPaid: false,
        methodAdded: MethodAdded.csv,
      ),
      name == ""
          ? null
          : TransactionAssociatedTitle(
              associatedTitlePk: "-1",
              categoryFk: mainCategoryFk,
              isExactMatch: false,
              title: name.trim(),
              dateCreated: dateCreated,
              dateTimeModified: DateTime.now(),
              order: 0,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ProgressBar(
          currentPercent: currentPercent,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 10),
        TextFont(
          fontSize: 15,
          text: "${currentEntryIndex.toString()} / ${currentFileLength.toString()}",
        ),
      ],
    );
  }
}

int? _findListIndexWithMultipleNonEmptyStrings(List<List<String>> lists,
    {int? afterIndex}) {
  for (int i = 0; i < lists.length; i++) {
    if (afterIndex != null && i <= afterIndex) {
      continue;
    }
    List<String> innerList = lists[i];
    int nonEmptyCount = innerList.where((str) => str.isNotEmpty).length;
    if (nonEmptyCount > 3) {
      return i;
    }
  }
  return null;
}
