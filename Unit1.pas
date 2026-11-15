unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, LCLIntf, LCLType, Math;

const
  INSIDE = 0;
  LEFT   = 1;
  RIGHT  = 2;
  TOP    = 4;
  BOTTOM = 8;

type

  TSegment = record
    X1, Y1, X2, Y2: Integer;   // исходные (введённые) координаты отрезка
    Visible: Boolean;          // виден ли отрезок после отсечения
    CX1, CY1, CX2, CY2: real;  // координаты видимой части после отсечения
  end;

  { TForm1 }

  TForm1 = class(TForm)
    PaintBox1: TPaintBox;
    ButtonClip: TButton;
    ButtonClear: TButton;
    EditWinLeft: TEdit;
    EditWinTop: TEdit;
    EditWinRight: TEdit;
    EditWinBottom: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure PaintBox1Paint(Sender: TObject);
    procedure PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ButtonClipClick(Sender: TObject);
    procedure ButtonClearClick(Sender: TObject);
  private
    Segments: array of TSegment;
    HasFirstPoint: Boolean;
    FirstX, FirstY: Integer;
    ClippingDone: Boolean;
    function GetWindowRect(out xmin, ymin, xmax, ymax: Integer): Boolean;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

// ---------------------------------------------------------------------
// Код Сазерленда-Коэна для точки (x,y) относительно окна [xmin..xmax]x[ymin..ymax].
// Биты: LEFT - левее окна, RIGHT - правее, TOP - выше (y меньше ymin),
// BOTTOM - ниже (y больше ymax).
// ---------------------------------------------------------------------
function ComputeCode(x, y, xmin, ymin, xmax, ymax: real): Integer;
var
  code: Integer;
begin
  code := INSIDE;
  if x < xmin then
    code := code or LEFT
  else if x > xmax then
    code := code or RIGHT;
  if y < ymin then
    code := code or TOP
  else if y > ymax then
    code := code or BOTTOM;
  Result := code;
end;

// ---------------------------------------------------------------------
// Алгоритм Сазерленда-Коэна отсечения отрезка (x1,y1)-(x2,y2) прямоугольным
// окном. Возвращает True, если видимая часть отрезка существует (и тогда
// x1,y1,x2,y2 заменяются координатами видимой части).
// ---------------------------------------------------------------------
function ClipCohenSutherland(var x1, y1, x2, y2: real;
  xmin, ymin, xmax, ymax: real): Boolean;
var
  code1, code2, codeOut: Integer;
  x, y: real;
  accept, done: Boolean;
begin
  code1 := ComputeCode(x1, y1, xmin, ymin, xmax, ymax);
  code2 := ComputeCode(x2, y2, xmin, ymin, xmax, ymax);
  accept := False;
  done := False;
  x := 0; y := 0;

  while not done do
  begin
    if (code1 or code2) = 0 then
    begin
      // оба конца внутри окна - отрезок полностью видим
      accept := True;
      done := True;
    end
    else if (code1 and code2) <> 0 then
    begin
      // оба конца лежат вне окна с одной и той же стороны - отрезок
      // тривиально невидим целиком
      accept := False;
      done := True;
    end
    else
    begin
      // хотя бы один конец вне окна, но не тривиально невидим -
      // берём его код и находим пересечение с соответствующей стороной окна
      if code1 <> 0 then
        codeOut := code1
      else
        codeOut := code2;

      if (codeOut and TOP) <> 0 then
      begin
        x := x1 + (x2 - x1) * (ymin - y1) / (y2 - y1);
        y := ymin;
      end
      else if (codeOut and BOTTOM) <> 0 then
      begin
        x := x1 + (x2 - x1) * (ymax - y1) / (y2 - y1);
        y := ymax;
      end
      else if (codeOut and RIGHT) <> 0 then
      begin
        y := y1 + (y2 - y1) * (xmax - x1) / (x2 - x1);
        x := xmax;
      end
      else // LEFT
      begin
        y := y1 + (y2 - y1) * (xmin - x1) / (x2 - x1);
        x := xmin;
      end;

      if codeOut = code1 then
      begin
        x1 := x;
        y1 := y;
        code1 := ComputeCode(x1, y1, xmin, ymin, xmax, ymax);
      end
      else
      begin
        x2 := x;
        y2 := y;
        code2 := ComputeCode(x2, y2, xmin, ymin, xmax, ymax);
      end;
    end;
  end;
  Result := accept;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  EditWinLeft.Text := '100';
  EditWinTop.Text := '80';
  EditWinRight.Text := '380';
  EditWinBottom.Text := '280';
  HasFirstPoint := False;
  ClippingDone := False;
  SetLength(Segments, 0);
end;

function TForm1.GetWindowRect(out xmin, ymin, xmax, ymax: Integer): Boolean;
var
  a, b, c, d: Integer;
begin
  if not TryStrToInt(Trim(EditWinLeft.Text), a) then a := 100;
  if not TryStrToInt(Trim(EditWinTop.Text), b) then b := 80;
  if not TryStrToInt(Trim(EditWinRight.Text), c) then c := 380;
  if not TryStrToInt(Trim(EditWinBottom.Text), d) then d := 280;
  xmin := Min(a, c);
  xmax := Max(a, c);
  ymin := Min(b, d);
  ymax := Max(b, d);
  Result := True;
end;

// ---------------------------------------------------------------------
// Отрисовка: окно отсечения, все введённые отрезки (серым пунктиром),
// а после нажатия "Отсечь" поверх них - видимые части (зелёным) или
// отметка "невидим" для отрезков, полностью лежащих вне окна.
// ---------------------------------------------------------------------
procedure TForm1.PaintBox1Paint(Sender: TObject);
var
  xmin, ymin, xmax, ymax: Integer;
  i: Integer;
  cnv: TCanvas;
begin
  cnv := PaintBox1.Canvas;
  cnv.Brush.Color := RGB(255, 255, 255);
  cnv.FillRect(PaintBox1.ClientRect);

  GetWindowRect(xmin, ymin, xmax, ymax);
  cnv.Brush.Style := bsClear;
  cnv.Pen.Style := psSolid;
  cnv.Pen.Width := 2;
  cnv.Pen.Color := RGB(0, 90, 200);
  cnv.Rectangle(xmin, ymin, xmax, ymax);
  cnv.Pen.Width := 1;

  for i := 0 to High(Segments) do
  begin
    // исходный отрезок целиком - серым пунктиром
    cnv.Pen.Style := psDash;
    cnv.Pen.Color := RGB(160, 160, 160);
    cnv.Line(Segments[i].X1, Segments[i].Y1, Segments[i].X2, Segments[i].Y2);

    if ClippingDone and Segments[i].Visible then
    begin
      // видимая после отсечения часть - зелёным, толще
      cnv.Pen.Style := psSolid;
      cnv.Pen.Color := RGB(0, 170, 0);
      cnv.Pen.Width := 3;
      cnv.Line(round(Segments[i].CX1), round(Segments[i].CY1),
               round(Segments[i].CX2), round(Segments[i].CY2));
      cnv.Pen.Width := 1;
    end;
  end;

  // точка первого клика, ожидающая второй клик
  if HasFirstPoint then
  begin
    cnv.Pen.Style := psSolid;
    cnv.Brush.Style := bsSolid;
    cnv.Brush.Color := RGB(220, 0, 0);
    cnv.Ellipse(FirstX - 3, FirstY - 3, FirstX + 3, FirstY + 3);
    cnv.Brush.Style := bsClear;
  end;
end;

// ---------------------------------------------------------------------
// Первый клик задаёт начало отрезка, второй - конец (и добавляет отрезок
// в список). Каждая новая пара кликов - новый отрезок.
// ---------------------------------------------------------------------
procedure TForm1.PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  n: Integer;
begin
  if Button <> mbLeft then Exit;

  if not HasFirstPoint then
  begin
    FirstX := X;
    FirstY := Y;
    HasFirstPoint := True;
  end
  else
  begin
    n := Length(Segments);
    SetLength(Segments, n + 1);
    Segments[n].X1 := FirstX;
    Segments[n].Y1 := FirstY;
    Segments[n].X2 := X;
    Segments[n].Y2 := Y;
    Segments[n].Visible := False;
    HasFirstPoint := False;
    ClippingDone := False;
  end;
  PaintBox1.Invalidate;
end;

procedure TForm1.ButtonClipClick(Sender: TObject);
var
  xmin, ymin, xmax, ymax: Integer;
  i: Integer;
  cx1, cy1, cx2, cy2: real;
begin
  if Length(Segments) = 0 then
  begin
    ShowMessage('Сначала задайте хотя бы один отрезок: кликните дважды на поле (начало и конец отрезка).');
    Exit;
  end;

  GetWindowRect(xmin, ymin, xmax, ymax);

  for i := 0 to High(Segments) do
  begin
    cx1 := Segments[i].X1; cy1 := Segments[i].Y1;
    cx2 := Segments[i].X2; cy2 := Segments[i].Y2;
    Segments[i].Visible := ClipCohenSutherland(cx1, cy1, cx2, cy2,
      xmin, ymin, xmax, ymax);
    if Segments[i].Visible then
    begin
      Segments[i].CX1 := cx1; Segments[i].CY1 := cy1;
      Segments[i].CX2 := cx2; Segments[i].CY2 := cy2;
    end;
  end;

  ClippingDone := True;
  PaintBox1.Invalidate;
end;

procedure TForm1.ButtonClearClick(Sender: TObject);
begin
  SetLength(Segments, 0);
  HasFirstPoint := False;
  ClippingDone := False;
  PaintBox1.Invalidate;
end;

end.
