import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:google_maps_place_picker_mb/providers/place_provider.dart';
import 'package:google_maps_place_picker_mb/providers/search_provider.dart';
import 'package:google_maps_place_picker_mb/src/components/prediction_tile.dart';
import 'package:google_maps_place_picker_mb/src/controllers/autocomplete_search_controller.dart';
import 'package:flutter_google_maps_webservices/places.dart';
import 'package:provider/provider.dart';

class AutoCompleteSearch extends StatefulWidget {
  const AutoCompleteSearch(
      {Key? key,
      required this.sessionToken,
      required this.onPicked,
      required this.appBarKey,
      this.hintText = "Search here",
      this.searchingText = "Searching...",
      this.hidden = false,
      this.height = 46,
      this.contentPadding = EdgeInsets.zero,
      this.debounceMilliseconds,
      this.onSearchFailed,
      required this.searchBarController,
      this.autocompleteOffset,
      this.autocompleteRadius,
      this.autocompleteLanguage,
      this.autocompleteComponents,
      this.autocompleteTypes,
      this.strictbounds,
      this.region,
      this.initialSearchString,
      this.searchForInitialValue,
      this.autocompleteOnTrailingWhitespace})
      : assert(searchBarController != null),
        super(key: key);

  final String? sessionToken;
  final String? hintText;
  final String? searchingText;
  final bool hidden;
  final double height;
  final EdgeInsetsGeometry contentPadding;
  final int? debounceMilliseconds;
  final ValueChanged<Prediction> onPicked;
  final ValueChanged<String>? onSearchFailed;
  final SearchBarController searchBarController;
  final num? autocompleteOffset;
  final num? autocompleteRadius;
  final String? autocompleteLanguage;
  final List<String>? autocompleteTypes;
  final List<Component>? autocompleteComponents;
  final bool? strictbounds;
  final String? region;
  final GlobalKey appBarKey;
  final String? initialSearchString;
  final bool? searchForInitialValue;
  final bool? autocompleteOnTrailingWhitespace;

  @override
  AutoCompleteSearchState createState() => AutoCompleteSearchState();
}

class AutoCompleteSearchState extends State<AutoCompleteSearch> {
  TextEditingController controller = TextEditingController();
  FocusNode focus = FocusNode();
  OverlayEntry? overlayEntry;
  SearchProvider provider = SearchProvider();

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchString != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.text = widget.initialSearchString!;
        if (widget.searchForInitialValue!) {
          _onSearchInputChange();
        }
      });
    }
    controller.addListener(_onSearchInputChange);
    focus.addListener(_onFocusChanged);

    widget.searchBarController.attach(this);
  }

  @override
  void dispose() {
    controller.removeListener(_onSearchInputChange);
    controller.dispose();

    focus.removeListener(_onFocusChanged);
    focus.dispose();
    _clearOverlay();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return !widget.hidden
        ? ChangeNotifierProvider.value(
            value: provider,
            child: Container(
              height: widget.height,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                elevation: 4,
                shadowColor: Colors.black12,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.search,
                        color: Color.fromRGBO(0, 183, 240, 1),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: _buildSearchTextField()),
                      _buildTextClearIcon(),
                    ],
                  ),
                ),
              ),
            ),
          )
        : Container();
  }

  Widget _buildSearchTextField() {
    return TextField(
      controller: controller,
      focusNode: focus,
      style: TextStyle(
        fontSize: 16,
        height: 1.4,
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white60
              : Colors.black38,
          fontSize: 16,
          height: 1.4,
        ),
        border: InputBorder.none,
        errorBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: true,
        contentPadding: widget.contentPadding,
      ),
    );
  }

  Widget _buildTextClearIcon() {
    return Selector<SearchProvider, String>(
        selector: (_, provider) => provider.searchTerm,
        builder: (_, data, __) {
          if (data.length > 0) {
            return Material(
              type: MaterialType.circle,
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ),
                onTap: () {
                  clearText();
                },
              ),
            );
          } else {
            return SizedBox(width: 8);
          }
        });
  }

  _onSearchInputChange() {
    if (!mounted) return;
    this.provider.searchTerm = controller.text;

    PlaceProvider provider = PlaceProvider.of(context, listen: false);

    if (controller.text.isEmpty) {
      provider.debounceTimer?.cancel();
      _searchPlace(controller.text);
      return;
    }

    if (controller.text.trim() == this.provider.prevSearchTerm.trim()) {
      provider.debounceTimer?.cancel();
      return;
    }

    if (!widget.autocompleteOnTrailingWhitespace! &&
        controller.text.substring(controller.text.length - 1) == " ") {
      provider.debounceTimer?.cancel();
      return;
    }

    if (provider.debounceTimer?.isActive ?? false) {
      provider.debounceTimer!.cancel();
    }

    provider.debounceTimer =
        Timer(Duration(milliseconds: widget.debounceMilliseconds!), () {
      _searchPlace(controller.text.trim());
    });
  }

  _onFocusChanged() {
    PlaceProvider provider = PlaceProvider.of(context, listen: false);
    provider.isSearchBarFocused = focus.hasFocus;
    provider.debounceTimer?.cancel();
    provider.placeSearchingState = SearchingState.Idle;
  }

  _searchPlace(String searchTerm) {
    this.provider.prevSearchTerm = searchTerm;

    _clearOverlay();

    if (searchTerm.length < 1) return;

    _displayOverlay(_buildSearchingOverlay());

    _performAutoCompleteSearch(searchTerm);
  }

  _clearOverlay() {
    if (overlayEntry != null) {
      overlayEntry!.remove();
      overlayEntry = null;
    }
  }

  _displayOverlay(Widget overlayChild) {
    _clearOverlay();

    final RenderBox? appBarRenderBox =
        widget.appBarKey.currentContext!.findRenderObject() as RenderBox?;
    final translation = appBarRenderBox?.getTransformTo(null).getTranslation();
    final Offset offset = translation != null
        ? Offset(translation.x, translation.y)
        : Offset(0.0, 0.0);
    final screenWidth = MediaQuery.of(context).size.width;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: appBarRenderBox!.paintBounds.shift(offset).top +
            appBarRenderBox.size.height,
        left: screenWidth * 0.025,
        right: screenWidth * 0.025,
        child: Material(
          elevation: 4.0,
          child: overlayChild,
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry!);
  }

  Widget _buildSearchingOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: <Widget>[
          SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 24),
          Expanded(
            child: Text(
              widget.searchingText ?? "Searching...",
              style: TextStyle(fontSize: 16),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPredictionOverlay(List<Prediction> predictions) {
    return ListBody(
      children: predictions
          .map(
            (p) => PredictionTile(
              prediction: p,
              onTap: (selectedPrediction) {
                resetSearchBar();
                widget.onPicked(selectedPrediction);
              },
            ),
          )
          .toList(),
    );
  }

  _performAutoCompleteSearch(String searchTerm) async {
    PlaceProvider provider = PlaceProvider.of(context, listen: false);

    if (searchTerm.isNotEmpty) {
      final PlacesAutocompleteResponse response =
          await provider.places.autocomplete(
        searchTerm,
        sessionToken: widget.sessionToken,
        location: provider.currentPosition == null
            ? null
            : Location(
                lat: provider.currentPosition!.latitude,
                lng: provider.currentPosition!.longitude),
        offset: widget.autocompleteOffset,
        radius: widget.autocompleteRadius,
        language: widget.autocompleteLanguage,
        types: widget.autocompleteTypes ?? const [],
        components: widget.autocompleteComponents ?? const [],
        strictbounds: widget.strictbounds ?? false,
        region: widget.region,
      );

      if (response.errorMessage?.isNotEmpty == true ||
          response.status == "REQUEST_DENIED") {
        if (widget.onSearchFailed != null) {
          widget.onSearchFailed!(response.status);
        }
        return;
      }

      _displayOverlay(_buildPredictionOverlay(response.predictions));
    }
  }

  clearText() {
    provider.searchTerm = "";
    controller.clear();
  }

  resetSearchBar() {
    clearText();
    focus.unfocus();
  }

  clearOverlay() {
    _clearOverlay();
  }
}
