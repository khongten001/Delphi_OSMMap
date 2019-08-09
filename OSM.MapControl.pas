{
  Visual control displaying a map.
  Data for the map (tile images) must be supplied via callbacks.
  See OSM.TileStorage unit
}
unit OSM.MapControl;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Math, Types,
  OSM.SlippyMapUtils;

const
  // default W and H of cache image in number of tiles.
  // Image's memory occupation:
  //   (4 bytes per pixel)*TilesH*TilesV*(65536 pixels in single tile)
  // For value 8 it counts 16.7 Mb
  CacheImageDefTilesH = 8;
  CacheImageDefTilesV = 8;
  // default W and H of cache image in pixels
  CacheImageDefWidth = CacheImageDefTilesH*TILE_IMAGE_WIDTH;
  CacheImageDefHeight = CacheImageDefTilesV*TILE_IMAGE_HEIGHT;
  // margin that is added to cache image to hold view area, in number of tiles
  CacheMarginSize = 2;
  // size of margin for labels on map, in pixels
  LabelMargin = 2;

type
  TMapOption = (
    moDontDrawCopyright,
    moDontDrawScale
  );

  TMapOptions = set of TMapOption;

  TMapMark = record
    {}// TODO
  end;
  PMapMark = ^TMapMark;

  TMapControl = class;

  // Callback to get bitmap of a single tile having number (TileHorzNum;TileVertNum)
  // If TileBmp is returned nil, DrawTileLoading method is called for this tile
  // Generally you must assign this callback only.
  TOnGetTile = procedure (Sender: TMapControl; TileHorzNum, TileVertNum: Cardinal;
    out TileBmp: TBitmap) of object;

  // Callback to draw bitmap of a single tile having number (TileHorzNum;TileVertNum)
  // If OnDrawTile assigned, it means fully custom drawing process, f.ex. if user has
  // fast tile sources that are not TBitmap-s, and it is user responsibility to indicate
  // tiles that are loading at the moment.
  // If OnDrawTileLoading assigned, the handler will be called only for empty tiles
  // allowing a user to draw his own label
  TOnDrawTile = procedure (Sender: TMapControl; TileHorzNum, TileVertNum: Cardinal;
    const TopLeft: TPoint; DestBmp: TBitMap) of object;

  // Virtual control that doesn't hold any data and must be painted by callbacks
  TMapControl = class(TScrollBox)
  strict private
    FMapSize: TSize;         // current map dims in pixels
    FCacheImage: TBitmap;    // drawn tiles (it could be equal to or larger than view area!)
    FCopyright,              // lazily created cache images for
    FScaleLine: TBitmap;     //    scale line and copyright
    FZoom: Integer;          // current zoom; integer for simpler operations
    FCacheImageRect: TRect;  // position of cache image on map in map coords
    FMapOptions: TMapOptions;
    FDragPos: TPoint;
    FOnGetTile: TOnGetTile;
    FOnDrawTile: TOnDrawTile;
    FOnDrawTileLoading: TOnDrawTile;
    FOnZoomChanged: TNotifyEvent;
  protected
    // overrides
    procedure PaintWindow(DC: HDC); override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function MouseActivate(Button: TMouseButton; Shift: TShiftState; X, Y: Integer; HitTest: Integer): TMouseActivate; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure DragOver(Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean); override;
    procedure WMHScroll(var Message: TWMHScroll); message WM_HSCROLL;
    procedure WMVScroll(var Message: TWMVScroll); message WM_VSCROLL;
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    // main methods
    function ViewInCache: Boolean;
    procedure UpdateCache;
    procedure MoveCache;
    function SetCacheDimensions: Boolean;
    function FindNextMapMark(const Pt: TPoint; PrevIndex: Integer = -1): Integer;
    procedure DrawTileLoading(TileHorzNum, TileVertNum: Cardinal; const TopLeft: TPoint; DestBmp: TBitMap);
    procedure DoDrawTile(TileHorzNum, TileVertNum: Cardinal; const TopLeft: TPoint; DestBmp: TBitMap);
    // helpers
    function ViewAreaRect: TRect;

    procedure SetNWPoint(const MapPt: TPoint); overload;
    function GetCenterPoint: TPointF;
    procedure SetCenterPoint(const Coords: TPointF);
    function GetNWPoint: TPointF;
    procedure SetNWPoint(const GeoCoords: TPointF); overload;

    class procedure DrawCopyright(const Text: string; DestBmp: TBitmap);
    class procedure DrawScale(Zoom: TMapZoomLevel; DestBmp: TBitmap);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure RefreshTile(TileHorzNum, TileVertNum: Cardinal);

    function MapToGeoCoords(const MapPt: TPoint): TPointF;
    function GeoCoordsToMap(const GeoCoords: TPointF): TPoint;
    function ViewToMap(const ViewPt: TPoint): TPoint;
    function MapToView(const MapPt: TPoint): TPoint;

    procedure ScrollMapBy(DeltaHorz, DeltaVert: Integer);
    procedure ScrollMapTo(Horz, Vert: Integer);
    procedure SetZoom(Value: Integer; const ViewBindPoint: TPoint); overload;
    procedure SetZoom(Value: Integer); overload;

    {}
    {
     add/remove map marks
     MouseBox
    }
    property Zoom: Integer read FZoom;
    property MapOptions: TMapOptions read FMapOptions write FMapOptions;
    property CenterPoint: TPointF read GetCenterPoint write SetCenterPoint;
    property NWPoint: TPointF read GetNWPoint write SetNWPoint;
    property OnGetTile: TOnGetTile read FOnGetTile write FOnGetTile;
    property OnDrawTile: TOnDrawTile read FOnDrawTile write FOnDrawTile;
    property OnDrawTileLoading: TOnDrawTile read FOnDrawTileLoading write FOnDrawTileLoading;
    property OnZoomChanged: TNotifyEvent read FOnZoomChanged write FOnZoomChanged;
  end;

function ToInnerCoords(const StartPt, Pt: TPoint): TPoint; overload; inline;
function ToOuterCoords(const StartPt, Pt: TPoint): TPoint; overload; inline;
function ToInnerCoords(const StartPt: TPoint; const Rect: TRect): TRect; overload; inline;
function ToOuterCoords(const StartPt: TPoint; const Rect: TRect): TRect; overload; inline;

const
  SLbl_Loading = 'Loading [%d : %d]...';

implementation

// *** Utils ***

// Like Client<=>Screen

function ToInnerCoords(const StartPt, Pt: TPoint): TPoint;
begin
  Result := Pt.Subtract(StartPt);
end;

function ToOuterCoords(const StartPt, Pt: TPoint): TPoint;
begin
  Result := Pt.Add(StartPt);
end;

function ToInnerCoords(const StartPt: TPoint; const Rect: TRect): TRect;
begin
  Result.TopLeft := ToInnerCoords(StartPt, Rect.TopLeft);
  Result.BottomRight := ToInnerCoords(StartPt, Rect.BottomRight);
end;

function ToOuterCoords(const StartPt: TPoint; const Rect: TRect): TRect;
begin
  Result.TopLeft := ToOuterCoords(StartPt, Rect.TopLeft);
  Result.BottomRight := ToOuterCoords(StartPt, Rect.BottomRight);
end;

// Floor value to tile size

function ToTileWidthLesser(Width: Cardinal): Cardinal; inline;
begin
  Result := (Width div TILE_IMAGE_WIDTH)*TILE_IMAGE_WIDTH;
end;

function ToTileHeightLesser(Height: Cardinal): Cardinal; inline;
begin
  Result := (Height div TILE_IMAGE_HEIGHT)*TILE_IMAGE_HEIGHT;
end;

// Ceil value to tile size

function ToTileWidthGreater(Width: Cardinal): Cardinal; inline;
begin
  Result := ToTileWidthLesser(Width);
  if Width mod TILE_IMAGE_WIDTH > 0 then
    Inc(Result, TILE_IMAGE_WIDTH);
end;

function ToTileHeightGreater(Height: Cardinal): Cardinal; inline;
begin
  Result := ToTileHeightLesser(Height);
  if Height mod TILE_IMAGE_HEIGHT > 0 then
    Inc(Result, TILE_IMAGE_HEIGHT);
end;

{ TMapControl }

constructor TMapControl.Create(AOwner: TComponent);
begin
  inherited;
  FCacheImage := TBitmap.Create;

  FZoom := Pred(Integer(Low(TMapZoomLevel)));
  SetZoom(Low(TMapZoomLevel));
end;

destructor TMapControl.Destroy;
begin
  FreeAndNil(FCacheImage);
  FreeAndNil(FCopyright);
  FreeAndNil(FScaleLine);
  inherited;
end;

// *** overrides - events ***

// Main drawing routine
procedure TMapControl.PaintWindow(DC: HDC);
var
  ViewRect: TRect;
begin
  ViewRect := ViewAreaRect;
  // if view area lays within cached image, no update required
  if not FCacheImageRect.Contains(ViewRect) then
  begin
    MoveCache;
    UpdateCache;
  end;

  // convert ViewRect to CacheImage coords
  ViewRect := ToInnerCoords(FCacheImageRect.TopLeft, ViewRect);

  // draw cache (map background)
  // ! partial copying from source, TGraphic/TCanvas.Draw can't do that :(
  BitBlt(DC,
    0, 0, ViewRect.Width, ViewRect.Height,
    FCacheImage.Canvas.Handle, ViewRect.Left, ViewRect.Top, SRCCOPY);

  // init copyright bitmap if not inited yet and draw it
  if not (moDontDrawCopyright in FMapOptions) then
  begin
    if FCopyright = nil then
    begin
      FCopyright := TBitmap.Create;
      DrawCopyright(TilesCopyright, FCopyright);
    end;
    TransparentBlt(DC,
      ClientWidth - FCopyright.Width - LabelMargin,
      ClientHeight - FCopyright.Height - LabelMargin,
      FCopyright.Width,
      FCopyright.Height,
      FCopyright.Canvas.Handle,
      0, 0,
      FCopyright.Width,
      FCopyright.Height,
      clWhite);
  end;

  // scaleline bitmap must've been inited already in SetZoom
  if not (moDontDrawScale in FMapOptions) then
  begin
    BitBlt(DC,
      LabelMargin,
      ClientHeight - FScaleLine.Height - LabelMargin,
      FScaleLine.Width,
      FScaleLine.Height,
      FScaleLine.Canvas.Handle,
      0, 0, SRCCOPY);
  end;
end;

// NB: painting on TWinControl is pretty tricky, doing it ordinary way leads
// to weird effects as DC's do not cover whole client area.
// Luckily this could be solved with Invalidate which fully redraws the control
procedure TMapControl.WMHScroll(var Message: TWMHScroll);
begin
  Invalidate;
  inherited;
end;

procedure TMapControl.WMVScroll(var Message: TWMVScroll);
begin
  Invalidate;
  inherited;
end;

// ! Only with csCustomPaint ControlState the call chain
// TWinControl.WMPaint > PaintHandler > PaintWindow will be executed.
procedure TMapControl.WMPaint(var Message: TWMPaint);
begin
  ControlState := ControlState + [csCustomPaint];
  inherited;
  ControlState := ControlState - [csCustomPaint];
end;

// Reposition cache
procedure TMapControl.Resize;
begin
  if SetCacheDimensions then
    UpdateCache;
  Invalidate;
  inherited;
end;

// Start dragging on mouse press
procedure TMapControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FindNextMapMark(ViewToMap(Point(X, Y))) = -1 then
    BeginDrag(False, -1);  // < 0 - use the DragThreshold property of the global Mouse variable (c) help
  inherited;
end;

// Focus self on mouse press
function TMapControl.MouseActivate(Button: TMouseButton; Shift: TShiftState; X, Y, HitTest: Integer): TMouseActivate;
begin
  SetFocus;
  Result := inherited;
end;

// Zoom in/out on mouse wheel
function TMapControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  inherited;
  SetZoom(Zoom + Sign(WheelDelta), ScreenToClient(MousePos));
  Result := True;
end;

// Process dragging
procedure TMapControl.DragOver(Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
begin
  inherited;

  Accept := True;

  case State of
    dsDragEnter: // drag started - save initial drag position
      FDragPos := Point(X, Y);
    dsDragMove: // dragging - move the map
      begin
        ScrollMapBy(FDragPos.X - X, FDragPos.Y - Y);
        FDragPos := Point(X, Y);
      end;
  end;
end;

// *** new methods ***

// Set zoom level to Value and reposition to given point
//   ViewBindPoint - point in view area's coords that must keep its position
procedure TMapControl.SetZoom(Value: Integer; const ViewBindPoint: TPoint);
var
  CurrBindPt, NewViewNW: TPoint;
  BindCoords: TPointF;
begin
  if not (Value in [Low(TMapZoomLevel)..High(TMapZoomLevel)]) then Exit;
  if Value = FZoom then Exit;

  // save bind point if zoom is valid (zoom value is used to calc geo coords)
  if FZoom in [Low(TMapZoomLevel)..High(TMapZoomLevel)]
    then BindCoords := MapToGeoCoords(ViewToMap(ViewBindPoint))
    else BindCoords := OSM.SlippyMapUtils.MapToGeoCoords(Point(0, 0), 0);

  FZoom := Value;
  FMapSize.cx := TileCount(FZoom)*TILE_IMAGE_WIDTH;
  FMapSize.cy := TileCount(FZoom)*TILE_IMAGE_HEIGHT;

  HorzScrollBar.Range := FMapSize.cx;
  VertScrollBar.Range := FMapSize.cy;

  // init copyright bitmap if not inited yet and draw it
  if not (moDontDrawScale in FMapOptions) then
  begin
    if FScaleLine = nil then
      FScaleLine := TBitmap.Create;
    DrawScale(FZoom, FScaleLine);
  end;

  // move viewport
  CurrBindPt := GeoCoordsToMap(BindCoords); // bind point in new map coords
  NewViewNW := CurrBindPt.Subtract(ViewBindPoint); // view's top-left corner in new map coords
  SetNWPoint(NewViewNW);

  SetCacheDimensions;
  if not FCacheImageRect.Contains(ViewAreaRect) then
    MoveCache;
  UpdateCache; // zoom changed - update cache anyway

  Refresh;

  if Assigned(FOnZoomChanged) then
    FOnZoomChanged(Self);
end;

// Simple zoom change with binding to top-left corner
procedure TMapControl.SetZoom(Value: Integer);
begin
  SetZoom(Value, Point(0,0));
end;

// Determines cache image size according to control and map size
// Returns true if size was changed
function TMapControl.SetCacheDimensions: Boolean;
var
  CtrlSize, CacheSize: TSize;
begin
  // dims of view area in pixels rounded to full tiles
  CtrlSize.cx := ToTileWidthGreater(ClientWidth);
  CtrlSize.cy := ToTileHeightGreater(ClientHeight);

  // cache dims = Max(control+margins, Min(map, default+margins))
  CacheSize.cx := Min(FMapSize.cx, CacheImageDefWidth + CacheMarginSize*TILE_IMAGE_WIDTH);
  CacheSize.cy := Min(FMapSize.cy, CacheImageDefHeight + CacheMarginSize*TILE_IMAGE_HEIGHT);

  CacheSize.cx := Max(CacheSize.cx, CtrlSize.cx + CacheMarginSize*TILE_IMAGE_WIDTH);
  CacheSize.cy := Max(CacheSize.cy, CtrlSize.cy + CacheMarginSize*TILE_IMAGE_HEIGHT);

  Result := (FCacheImageRect.Width <> CacheSize.cx) or (FCacheImageRect.Height <> CacheSize.cy);
  if not Result then Exit;
  FCacheImageRect.Size := CacheSize;
  FCacheImage.SetSize(CacheSize.cx, CacheSize.cy);
end;

// Recalc point in view area coords to map coords
function TMapControl.ViewToMap(const ViewPt: TPoint): TPoint;
begin
  Result := ToOuterCoords(ViewAreaRect.TopLeft, ViewPt);
end;

// Recalc point in map coords to view area coords
function TMapControl.MapToView(const MapPt: TPoint): TPoint;
begin
  Result := ToInnerCoords(ViewAreaRect.TopLeft, MapPt);
end;

// View area position and size in map coords
function TMapControl.ViewAreaRect: TRect;
begin
  Result := ClientRect;
  Result.Offset(Point(HorzScrollBar.Position, VertScrollBar.Position));
end;

// Whether view area is inside cache image
function TMapControl.ViewInCache: Boolean;
begin
  Result := FCacheImageRect.Contains(ViewAreaRect);
end;

// Fill the cache image
procedure TMapControl.UpdateCache;
var
  CanvRect: TRect;
  CacheHorzCount, CacheVertCount, horz, vert, CacheHorzNum, CacheVertNum: Cardinal;
begin
  // Bounds of cache image in its own coords
  CanvRect := FCacheImageRect;
  CanvRect.SetLocation(0, 0);
  // Clear the image
  FCacheImage.Canvas.Brush.Color := Self.Color;
  FCacheImage.Canvas.FillRect(CanvRect);
  // Get dimensions of cache
  CacheHorzCount := Min(FMapSize.cx - FCacheImageRect.Left, FCacheImageRect.Width) div TILE_IMAGE_WIDTH;
  CacheVertCount := Min(FMapSize.cy - FCacheImageRect.Top, FCacheImageRect.Height) div TILE_IMAGE_HEIGHT;
  // Get top-left of cache in tiles
  CacheHorzNum := FCacheImageRect.Left div TILE_IMAGE_WIDTH;
  CacheVertNum := FCacheImageRect.Top div TILE_IMAGE_HEIGHT;
  // Draw cache tiles
  for horz := 0 to CacheHorzCount - 1 do
    for vert := 0 to CacheVertCount - 1 do
      DoDrawTile(CacheHorzNum + horz, CacheVertNum + vert, Point(horz*TILE_IMAGE_WIDTH, vert*TILE_IMAGE_HEIGHT), FCacheImage);
end;

// Calc new cache coords to cover current view area
procedure TMapControl.MoveCache;
var
  ViewRect: TRect;
  MarginH, MarginV: Cardinal;
begin
  ViewRect := ViewAreaRect;
  // move view rect to the border of tiles (to lesser value)
  ViewRect.Left := ToTileWidthLesser(ViewRect.Left);
  ViewRect.Top := ToTileHeightLesser(ViewRect.Top);
  // resize view rect to the border of tiles (to greater value)
  ViewRect.Right := ToTileWidthGreater(ViewRect.Right);
  ViewRect.Bottom := ToTileHeightGreater(ViewRect.Bottom);

  // reposition new cache rect to cover tile-aligned view area
  // calc margins
  MarginH := FCacheImageRect.Width - ViewRect.Width;
  MarginV := FCacheImageRect.Height - ViewRect.Height;
  // margins on the both sides
  if MarginH > TILE_IMAGE_WIDTH then
    MarginH := MarginH div 2;
  if MarginV > TILE_IMAGE_HEIGHT then
    MarginV := MarginV div 2;
  FCacheImageRect.SetLocation(ViewRect.TopLeft);
  FCacheImageRect.TopLeft.Subtract(Point(MarginH, MarginV));
end;

// Draw single tile (TileHorzNum;TileVertNum)
procedure TMapControl.RefreshTile(TileHorzNum, TileVertNum: Cardinal);
var
  TileTopLeft: TPoint;
begin
  // calc tile rect in map coords
  TileTopLeft := Point(TileHorzNum*TILE_IMAGE_WIDTH, TileVertNum*TILE_IMAGE_HEIGHT);
  // the tile is not in cache
  if not FCacheImageRect.Contains(TileTopLeft) then
    Exit;
  // convert tile to cache image coords
  TileTopLeft.SetLocation(ToInnerCoords(FCacheImageRect.TopLeft, TileTopLeft));
  // draw to cache
  DoDrawTile(TileHorzNum, TileVertNum, TileTopLeft, FCacheImage);
  // redraw the view
  Refresh;
end;

// Draw single tile (TileHorzNum;TileVertNum) to bitmap DestBmp at point TopLeft
procedure TMapControl.DoDrawTile(TileHorzNum, TileVertNum: Cardinal; const TopLeft: TPoint; DestBmp: TBitMap);
var
  TileBmp: TBitmap;
begin
  // check if user wants custom draw
  if Assigned(OnDrawTile) then
  begin
    OnDrawTile(Self, TileHorzNum, TileVertNum, TopLeft, DestBmp);
    Exit;
  end;
  // request tile bitmap via callback
  TileBmp := nil;
  if Assigned(OnGetTile) then
    OnGetTile(Self, TileHorzNum, TileVertNum, TileBmp);
  // no such tile - draw "loading"
  if TileBmp = nil then
  begin
    if Assigned(FOnDrawTileLoading) then
      FOnDrawTileLoading(Self, TileHorzNum, TileVertNum, TopLeft, DestBmp)
    else
      DrawTileLoading(TileHorzNum, TileVertNum, TopLeft, DestBmp);
  end
  else
    DestBmp.Canvas.Draw(TopLeft.X, TopLeft.Y, TileBmp);
end;

// Draw single tile (TileHorzNum;TileVertNum) loading to bitmap DestBmp at point TopLeft
procedure TMapControl.DrawTileLoading(TileHorzNum, TileVertNum: Cardinal; const TopLeft: TPoint; DestBmp: TBitMap);
var
  TileRect: TRect;
  TextExt: TSize;
  Canv: TCanvas;
  txt: string;
begin
  TileRect.TopLeft := TopLeft;
  TileRect.Size := TSize.Create(TILE_IMAGE_WIDTH, TILE_IMAGE_HEIGHT);

  Canv := DestBmp.Canvas;
  Canv.Brush.Color := Color;
  Canv.Pen.Color := clDkGray;
  Canv.Rectangle(TileRect);

  txt := Format(SLbl_Loading, [TileHorzNum, TileVertNum]);
  TextExt := Canv.TextExtent(txt);
  Canv.Font.Color := clGreen;
  Canv.TextOut(
    TileRect.Left + (TileRect.Width - TextExt.cx) div 2,
    TileRect.Top + (TileRect.Height - TextExt.cy) div 2,
    txt);
end;

// Draw copyright label on bitmap and set its size. Happens only once.
class procedure TMapControl.DrawCopyright(const Text: string; DestBmp: TBitmap);
var
  Canv: TCanvas;
  TextExt: TSize;
begin
  Canv := DestBmp.Canvas;

  Canv.Font.Name := 'Arial';
  Canv.Font.Size := 8;
  Canv.Font.Style := [];

  TextExt := Canv.TextExtent(Text);

  DestBmp.SetSize(TextExt.cx, TextExt.cy);

  // Text
  Canv.Font.Color := clGray;
  Canv.TextOut(LabelMargin, LabelMargin, Text);
end;

// Draw scale line on bitmap and set its size. Happens every zoom change.
class procedure TMapControl.DrawScale(Zoom: TMapZoomLevel; DestBmp: TBitmap);
var
  Canv: TCanvas;
  LetterWidth, ScalebarWidthPixel, ScalebarWidthMeter: Integer;
  Text: string;
  TextExt: TSize;
  ScalebarRect: TRect;
begin
  Canv := DestBmp.Canvas;

  GetScaleBarParams(Zoom, ScalebarWidthPixel, ScalebarWidthMeter, Text);

  Canv.Font.Name := 'Arial';
  Canv.Font.Size := 8;
  Canv.Font.Style := [];

  TextExt := Canv.TextExtent(Text);
  LetterWidth := Canv.TextWidth('W');

  DestBmp.Width := LetterWidth + TextExt.cx + LetterWidth + ScalebarWidthPixel; // text, space, bar
  DestBmp.Height := 2*LabelMargin + TextExt.cy;

  // Frame
  Canv.Brush.Color := clWhite;
  Canv.Pen.Color := clSilver;
  Canv.Rectangle(0, 0, DestBmp.Width, DestBmp.Height);

  // Text
  Canv.Font.Color := clBlack;
  Canv.TextOut(LetterWidth div 2, LabelMargin, Text);

  // Scale-Bar
  Canv.Brush.Color := clWhite;
  Canv.Pen.Color := clBlack;
  ScalebarRect.Left := LetterWidth div 2 + TextExt.cx + LetterWidth;
  ScalebarRect.Top := (DestBmp.Height - TextExt.cy div 2) div 2;
  ScalebarRect.Width := ScalebarWidthPixel;
  ScalebarRect.Height := TextExt.cy div 2;
  Canv.Rectangle(ScalebarRect);
end;

// Pixels => degrees
function TMapControl.MapToGeoCoords(const MapPt: TPoint): TPointF;
begin
  Result := OSM.SlippyMapUtils.MapToGeoCoords(MapPt, FZoom);
end;

// Degrees => pixels
function TMapControl.GeoCoordsToMap(const GeoCoords: TPointF): TPoint;
begin
  Result := OSM.SlippyMapUtils.GeoCoordsToMap(GeoCoords, FZoom);
end;

// Delta move the view area
procedure TMapControl.ScrollMapBy(DeltaHorz, DeltaVert: Integer);
begin
  Invalidate; // refresh the image
  HorzScrollBar.Position := HorzScrollBar.Position + DeltaHorz;
  VertScrollBar.Position := VertScrollBar.Position + DeltaVert;
end;

// Absolutely move the view area
procedure TMapControl.ScrollMapTo(Horz, Vert: Integer);
begin
  Invalidate; // refresh the image
  HorzScrollBar.Position := Horz;
  VertScrollBar.Position := Vert;
end;

// Move the view area to new top-left point
procedure TMapControl.SetNWPoint(const MapPt: TPoint);
begin
  ScrollMapTo(MapPt.X, MapPt.Y);
end;

{}//?
function TMapControl.GetCenterPoint: TPointF;
begin
  Result := MapToGeoCoords(ViewAreaRect.CenterPoint);
end;

procedure TMapControl.SetCenterPoint(const Coords: TPointF);
var
  ViewRect: TRect;
  Pt: TPoint;
begin
  // new center point in map coords
  Pt := GeoCoordsToMap(Coords);
  // new NW point
  ViewRect := ViewAreaRect;
  Pt.Offset(-ViewRect.Width div 2, -ViewRect.Height div 2);
  // move
  SetNWPoint(Pt);
end;

// Get top-left point of the view area
function TMapControl.GetNWPoint: TPointF;
begin
  Result := MapToGeoCoords(ViewAreaRect.TopLeft);
end;

// Move the view area to new top-left point
procedure TMapControl.SetNWPoint(const GeoCoords: TPointF);
begin
  SetNWPoint(GeoCoordsToMap(GeoCoords));
end;

// Find the next map mark that has specified coordinates.
//   PrevIndex - index of previous found map mark in the list. -1 (default) to
//     start from the 1st element.
// Returns:
//   index of map mark in the list, -1 if not found.
//
// Samples:
//   1) Check if there's any map marks at this point
//     if FindNextMapMark(Point) <> -1 then ...
//   2) Select all map marks at this point
//     idx := -1;
//     repeat
//       idx := FindNextMapMark(Point, idx);
//       if idx = -1 then Break;
//       ... do something with MapMarks[idx] ...
//     until False;
function TMapControl.FindNextMapMark(const Pt: TPoint; PrevIndex: Integer): Integer;
begin
  {
    if index = -1 - start searching
    if no marks - return -1
    if index > -1 - continue from index

  }

  {} Result := -1;
end;

end.