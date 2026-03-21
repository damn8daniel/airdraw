#!/usr/bin/env python3
"""
AirDraw — Рисование в воздухе с помощью жестов рук
MediaPipe Tasks API + Pygame
"""

import os
import sys
import time
import math
from enum import Enum, auto
from dataclasses import dataclass, field
from typing import Optional

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_tasks
from mediapipe.tasks.python import vision as mp_vision
import pygame
import pygame.freetype
import numpy as np

# ─────────────────────────────────────────────────────────────
# Константы
# ─────────────────────────────────────────────────────────────

WINDOW_W, WINDOW_H = 1280, 720
FPS = 60

PALETTE = [
    (255, 60,  60),   # Красный
    (255, 140,  0),   # Оранжевый
    (255, 230,  0),   # Жёлтый
    (60,  200,  60),  # Зелёный
    (0,   200, 240),  # Голубой
    (60,  100, 255),  # Синий
    (180,  60, 255),  # Фиолетовый
    (255, 80,  200),  # Розовый
    (255, 255, 255),  # Белый
]
PALETTE_NAMES = [
    "Красный", "Оранжевый", "Жёлтый", "Зелёный",
    "Голубой", "Синий", "Фиолетовый", "Розовый", "Белый"
]

UI_TEXT     = (220, 220, 220)
UI_ACCENT   = (100, 180, 255)
UI_SUCCESS  = (80, 220, 100)
UI_WARNING  = (255, 180, 50)
STATUS_IDLE = (150, 150, 150)

ALPHA_EMA      = 0.18   # Сглаживание позиции (меньше = плавнее)
ALPHA_DRAW     = 0.12   # Сглаживание при рисовании (ещё плавнее)
PINCH_DIST     = 0.07   # Порог щипка
MIN_MOVE_PX    = 4.0    # Минимальный шаг точки при рисовании
GESTURE_HOLD   = 1.4    # Секунд удержания для действия
GESTURE_STABLE = 5      # Кадров для стабилизации жеста

# Индексы ландмарков MediaPipe
WRIST      = 0
THUMB_TIP  = 4
INDEX_TIP  = 8
MIDDLE_TIP = 12
RING_TIP   = 16
PINKY_TIP  = 20
INDEX_MCP  = 5
MIDDLE_MCP = 9
RING_MCP   = 13
PINKY_MCP  = 17

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hand_landmarker.task")


# ─────────────────────────────────────────────────────────────
# Жесты
# ─────────────────────────────────────────────────────────────

class Gesture(Enum):
    UNKNOWN   = auto()
    POINTING  = auto()
    PINCHING  = auto()
    PEACE     = auto()
    OPEN_PALM = auto()
    FIST      = auto()


# ─────────────────────────────────────────────────────────────
# Детектор жестов (MediaPipe Tasks API)
# ─────────────────────────────────────────────────────────────

class HandDetector:
    def __init__(self):
        base_options = mp_tasks.BaseOptions(model_asset_path=MODEL_PATH)
        options = mp_vision.HandLandmarkerOptions(
            base_options=base_options,
            running_mode=mp_vision.RunningMode.VIDEO,
            num_hands=1,
            min_hand_detection_confidence=0.65,
            min_hand_presence_confidence=0.55,
            min_tracking_confidence=0.55,
        )
        self._detector = mp_vision.HandLandmarker.create_from_options(options)
        self._ts = 0

        # EMA сглаживание позиции
        self._sx = WINDOW_W / 2.0
        self._sy = WINDOW_H / 2.0

        # Дебаунс жеста: очередь последних N распознанных жестов
        self._g_buf = [Gesture.UNKNOWN] * GESTURE_STABLE
        self._stable_gesture = Gesture.UNKNOWN
        self.is_drawing = False   # внешний флаг — выбирает коэффициент сглаживания

        self.landmarks = None

    def process(self, bgr_frame: np.ndarray):
        """Возвращает (stable_Gesture, smooth_x, smooth_y)"""
        rgb = cv2.cvtColor(bgr_frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        self._ts += 33
        result = self._detector.detect_for_video(mp_image, self._ts)

        if not result.hand_landmarks:
            self.landmarks = None
            self._push_gesture(Gesture.UNKNOWN)
            return self._stable_gesture, self._sx, self._sy

        lm = result.hand_landmarks[0]
        self.landmarks = lm

        # Кадр уже зеркально отражён (cv2.flip), поэтому x НЕ инвертируем
        raw_x = lm[INDEX_TIP].x * WINDOW_W
        raw_y = lm[INDEX_TIP].y * WINDOW_H

        # EMA: более плавное при рисовании
        alpha = ALPHA_DRAW if self.is_drawing else ALPHA_EMA
        self._sx = alpha * raw_x + (1.0 - alpha) * self._sx
        self._sy = alpha * raw_y + (1.0 - alpha) * self._sy

        raw_g = self._classify(lm)
        self._push_gesture(raw_g)
        return self._stable_gesture, self._sx, self._sy

    def _push_gesture(self, g: Gesture):
        """Буфер дебаунса: жест считается стабильным когда все N последних одинаковые"""
        self._g_buf.pop(0)
        self._g_buf.append(g)
        if len(set(self._g_buf)) == 1:
            self._stable_gesture = g

    def _dist(self, a, b):
        return math.hypot(a.x - b.x, a.y - b.y)

    def _extended(self, tip, mcp, wrist):
        # Дополнительно смотрим на pip (среднюю точку пальца) для надёжности
        return self._dist(tip, wrist) > self._dist(mcp, wrist) * 1.15

    def _classify(self, lm):
        # Нормализованное расстояние щипка относительно размера ладони
        palm_size = self._dist(lm[WRIST], lm[MIDDLE_MCP])
        pinch_norm = self._dist(lm[THUMB_TIP], lm[INDEX_TIP]) / max(palm_size, 0.01)
        if pinch_norm < 0.28:
            return Gesture.PINCHING

        w  = lm[WRIST]
        ie = self._extended(lm[INDEX_TIP],  lm[INDEX_MCP],  w)
        me = self._extended(lm[MIDDLE_TIP], lm[MIDDLE_MCP], w)
        re = self._extended(lm[RING_TIP],   lm[RING_MCP],   w)
        pe = self._extended(lm[PINKY_TIP],  lm[PINKY_MCP],  w)

        if ie and me and re and pe:             return Gesture.OPEN_PALM
        if ie and me and not re and not pe:     return Gesture.PEACE
        if ie and not me and not re and not pe: return Gesture.POINTING
        if not ie and not me and not re and not pe: return Gesture.FIST
        return Gesture.UNKNOWN

    def lm_screen(self, idx: int):
        """Экранные координаты ландмарка (уже для зеркального кадра)"""
        l = self.landmarks[idx]
        return int(l.x * WINDOW_W), int(l.y * WINDOW_H)

    def skeleton_lines(self):
        if not self.landmarks:
            return []
        lm = self.landmarks
        conns = [
            (0,1),(1,2),(2,3),(3,4),
            (0,5),(5,6),(6,7),(7,8),
            (0,9),(9,10),(10,11),(11,12),
            (0,13),(13,14),(14,15),(15,16),
            (0,17),(17,18),(18,19),(19,20),
            (5,9),(9,13),(13,17)
        ]
        # Кадр уже зеркальный — x НЕ инвертируем
        return [
            ((int(lm[a].x*WINDOW_W), int(lm[a].y*WINDOW_H)),
             (int(lm[b].x*WINDOW_W), int(lm[b].y*WINDOW_H)))
            for a, b in conns
        ]

    def joint_points(self):
        if not self.landmarks:
            return []
        lm = self.landmarks
        pts = []
        for i, l in enumerate(lm):
            # Кадр уже зеркальный — x НЕ инвертируем
            x = int(l.x * WINDOW_W)
            y = int(l.y * WINDOW_H)
            pts.append((x, y, i in (4, 8, 12, 16, 20)))
        return pts

    def close(self):
        self._detector.close()


# ─────────────────────────────────────────────────────────────
# Холст рисования
# ─────────────────────────────────────────────────────────────

@dataclass
class Stroke:
    points: list = field(default_factory=list)
    color: tuple = (255, 60, 60)
    width: int = 5


class DrawingCanvas:
    def __init__(self):
        self.strokes: list[Stroke] = []
        self._current: Optional[Stroke] = None
        self._active = False
        self.color = PALETTE[0]
        self.width = 5
        self.color_idx = 0

    def start(self, x, y):
        self._current = Stroke(points=[(x, y)], color=self.color, width=self.width)
        self._active = True

    def add(self, x, y):
        if not self._active or not self._current:
            return
        if self._current.points:
            lx, ly = self._current.points[-1]
            if math.hypot(x - lx, y - ly) < MIN_MOVE_PX:
                return
        self._current.points.append((x, y))

    def end(self):
        if self._active and self._current and len(self._current.points) >= 2:
            self.strokes.append(self._current)
        self._current = None
        self._active = False

    def cancel(self):
        self._current = None
        self._active = False

    def undo(self):
        if self.strokes:
            self.strokes.pop()

    def clear(self):
        self.strokes.clear()
        self._current = None
        self._active = False

    def cycle_color(self):
        self.color_idx = (self.color_idx + 1) % len(PALETTE)
        self.color = PALETTE[self.color_idx]

    @property
    def is_active(self):
        return self._active

    def render(self, surf):
        for s in self.strokes:
            _draw_stroke(surf, s)
        if self._current:
            _draw_stroke(surf, self._current)


def _draw_stroke(surf, stroke: Stroke):
    pts = stroke.points
    if not pts:
        return
    if len(pts) == 1:
        pygame.draw.circle(surf, stroke.color,
                           (int(pts[0][0]), int(pts[0][1])), max(1, stroke.width // 2))
        return
    for i in range(1, len(pts)):
        p1 = (int(pts[i-1][0]), int(pts[i-1][1]))
        p2 = (int(pts[i][0]),   int(pts[i][1]))
        pygame.draw.line(surf, stroke.color, p1, p2, stroke.width)
        pygame.draw.circle(surf, stroke.color, p2, max(1, stroke.width // 2))


# ─────────────────────────────────────────────────────────────
# UI хелперы
# ─────────────────────────────────────────────────────────────

def draw_panel(surf, rect, alpha=195, radius=12):
    s = pygame.Surface((rect[2], rect[3]), pygame.SRCALPHA)
    pygame.draw.rect(s, (20, 20, 20, alpha), (0, 0, rect[2], rect[3]), border_radius=radius)
    surf.blit(s, (rect[0], rect[1]))


def draw_text(surf, font, text, pos, color=UI_TEXT, shadow=True):
    if shadow:
        font.render_to(surf, (pos[0]+1, pos[1]+1), text, (0, 0, 0))
    font.render_to(surf, pos, text, color)
    return font.get_rect(text).width


def text_w(font, text):
    return font.get_rect(text).width


# ─────────────────────────────────────────────────────────────
# Основное приложение
# ─────────────────────────────────────────────────────────────

class AirDrawApp:
    def __init__(self):
        pygame.init()
        pygame.freetype.init()
        pygame.display.set_caption("AirDraw — Рисование в воздухе")

        self.screen = pygame.display.set_mode((WINDOW_W, WINDOW_H))
        self.clock  = pygame.time.Clock()

        self.font_sm = pygame.freetype.SysFont("Arial", 14)
        self.font_md = pygame.freetype.SysFont("Arial", 17, bold=True)
        self.font_lg = pygame.freetype.SysFont("Arial", 22, bold=True)

        self.camera  = cv2.VideoCapture(0)
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        self.camera.set(cv2.CAP_PROP_FPS, 30)

        self.detector = HandDetector()
        self.canvas   = DrawingCanvas()

        self.gesture      = Gesture.UNKNOWN
        self.cx = WINDOW_W // 2
        self.cy = WINDOW_H // 2
        self.was_drawing  = False

        self.status_msg   = "Покажите руку камере"
        self.status_color = STATUS_IDLE

        self.show_camera   = True
        self.cam_alpha     = 255   # 0-255 (255 = без затемнения)
        self.show_skeleton = True

        self.hold_gesture  = None
        self.hold_start    = 0.0
        self.hold_progress = 0.0

        self.flash_msg = ""
        self.flash_end = 0.0

        self._mp_interval = 1.0 / 25
        self._last_mp     = 0.0
        self._cam_surf    = None

    # ── Главный цикл ──────────────────────────────────────────

    def run(self):
        running = True
        while running:
            self.clock.tick(FPS)

            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    self._on_key(event)

            # Кадр камеры
            ok, frame = self.camera.read()
            if ok:
                frame = cv2.flip(frame, 1)  # зеркало

                # MediaPipe детекция (25 fps)
                now = time.time()
                if now - self._last_mp >= self._mp_interval:
                    self._last_mp = now
                    self.detector.is_drawing = self.was_drawing
                    g, x, y = self.detector.process(frame)
                    self.gesture = g
                    self.cx, self.cy = x, y

                # Конвертация для pygame
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                rgb = np.transpose(rgb, (1, 0, 2))
                self._cam_surf = pygame.surfarray.make_surface(rgb)

            self._update_logic()
            self._render()

        self.camera.release()
        self.detector.close()
        pygame.quit()

    # ── Клавиши ────────────────────────────────────────────────

    def _on_key(self, event):
        ctrl = event.mod & (pygame.KMOD_META | pygame.KMOD_CTRL)
        if event.key == pygame.K_z and ctrl:
            self.canvas.undo()
            self._flash("Отмена")
        elif event.key == pygame.K_c and ctrl:
            self.canvas.clear()
            self._flash("Холст очищен")
        elif event.key == pygame.K_s and ctrl:
            self._save()
        elif event.key == pygame.K_ESCAPE:
            pygame.event.post(pygame.event.Event(pygame.QUIT))
        elif event.key == pygame.K_h:
            self.show_camera = not self.show_camera
        elif event.key == pygame.K_UP:
            self.canvas.width = min(30, self.canvas.width + 2)
        elif event.key == pygame.K_DOWN:
            self.canvas.width = max(2, self.canvas.width - 2)
        elif event.key == pygame.K_RIGHT:
            self.canvas.cycle_color()
            self._flash(f"Цвет: {PALETTE_NAMES[self.canvas.color_idx]}")

    # ── Логика жестов ──────────────────────────────────────────

    def _update_logic(self):
        g = self.gesture
        x, y = self.cx, self.cy

        # ☝️ УКАЗАТЕЛЬНЫЙ ПАЛЕЦ = РИСОВАТЬ
        if g == Gesture.POINTING:
            self._cancel_hold()
            if not self.was_drawing:
                self.canvas.start(x, y)
                self.was_drawing = True
            else:
                self.canvas.add(x, y)
            self.status_msg   = "Рисование..."
            self.status_color = self.canvas.color

        # ✌️ V-жест = поднять кисть (пауза) + удержать = сменить цвет
        elif g == Gesture.PEACE:
            self._end_draw()
            if self._hold(Gesture.PEACE):
                self.canvas.cycle_color()
                self._flash(f"Цвет: {PALETTE_NAMES[self.canvas.color_idx]}")
                self._cancel_hold()
            else:
                pct = int(self.hold_progress * 100)
                self.status_msg   = f"Удержите V-жест для смены цвета... {pct}%"
                self.status_color = UI_WARNING

        # ✋ Открытая ладонь = поднять кисть + удержать = очистить холст
        elif g == Gesture.OPEN_PALM:
            self._end_draw()
            if self._hold(Gesture.OPEN_PALM):
                self.canvas.clear()
                self._flash("Холст очищен!")
                self._cancel_hold()
            else:
                pct = int(self.hold_progress * 100)
                self.status_msg   = f"Удержите ладонь для очистки... {pct}%"
                self.status_color = UI_WARNING

        # 🤏 Щипок или ✊ кулак = пауза
        elif g in (Gesture.PINCHING, Gesture.FIST):
            self._end_draw()
            self._cancel_hold()
            self.status_msg   = "Пауза (покажите один палец чтобы рисовать)"
            self.status_color = STATUS_IDLE

        else:
            self._end_draw()
            self._cancel_hold()
            self.status_msg   = "Покажите руку камере"
            self.status_color = STATUS_IDLE

    def _end_draw(self):
        if self.was_drawing:
            self.canvas.end()
            self.was_drawing = False

    def _hold(self, g) -> bool:
        now = time.time()
        if self.hold_gesture != g:
            self.hold_gesture = g
            self.hold_start   = now
        self.hold_progress = min(1.0, (now - self.hold_start) / GESTURE_HOLD)
        return self.hold_progress >= 1.0

    def _cancel_hold(self):
        self.hold_gesture  = None
        self.hold_progress = 0.0

    def _flash(self, msg, dur=1.5):
        self.flash_msg = msg
        self.flash_end = time.time() + dur

    # ── Рендер ────────────────────────────────────────────────

    def _render(self):
        self.screen.fill((10, 10, 10))

        # Камера (без затемнения)
        if self.show_camera and self._cam_surf:
            s = pygame.transform.scale(self._cam_surf, (WINDOW_W, WINDOW_H))
            self.screen.blit(s, (0, 0))

        # Холст
        self.canvas.render(self.screen)

        # Скелет
        if self.show_skeleton:
            for (p1, p2) in self.detector.skeleton_lines():
                pygame.draw.line(self.screen, (60, 220, 90), p1, p2, 2)
            for (x, y, is_tip) in self.detector.joint_points():
                r = 5 if is_tip else 3
                c = (255, 255, 80) if is_tip else (60, 220, 90)
                pygame.draw.circle(self.screen, c, (x, y), r)

        # Курсор
        self._draw_cursor()

        # UI
        self._draw_top()
        self._draw_bottom()
        self._draw_flash()

        pygame.display.flip()

    def _draw_cursor(self):
        if self.gesture == Gesture.UNKNOWN:
            return
        cx, cy = int(self.cx), int(self.cy)
        col = self.canvas.color
        if self.gesture == Gesture.PINCHING:
            pygame.draw.circle(self.screen, col, (cx, cy), 10)
            pygame.draw.circle(self.screen, (255,255,255), (cx, cy), 10, 2)
        else:
            pygame.draw.circle(self.screen, col, (cx, cy), 18, 2)
            pygame.draw.circle(self.screen, (255,255,255), (cx, cy), 4)

        if self.hold_gesture and self.hold_progress > 0:
            angle = self.hold_progress * 360
            rect = pygame.Rect(cx-28, cy-28, 56, 56)
            pygame.draw.arc(self.screen, UI_WARNING, rect,
                            math.radians(90), math.radians(90 + angle), 3)

    def _draw_top(self):
        PAD = 14
        y   = 12

        # Палитра
        pal_w = len(PALETTE) * 36 + PAD * 2
        draw_panel(self.screen, (PAD, y, pal_w, 46))
        for i, col in enumerate(PALETTE):
            cx = PAD + PAD + i * 36 + 8
            cy = y + 23
            r  = 14 if i == self.canvas.color_idx else 10
            pygame.draw.circle(self.screen, col, (cx, cy), r)
            if i == self.canvas.color_idx:
                pygame.draw.circle(self.screen, (255,255,255), (cx, cy), r, 2)

        # Толщина
        bx = PAD + pal_w + 10
        draw_panel(self.screen, (bx, y, 135, 46))
        draw_text(self.screen, self.font_sm, "Толщина:", (bx+8, y+8))
        bw = 115
        pygame.draw.rect(self.screen, (60,60,60), (bx+8, y+30, bw, 4), border_radius=2)
        prog = (self.canvas.width - 2) / 28
        pygame.draw.rect(self.screen, UI_ACCENT, (bx+8, y+30, int(bw*prog), 4), border_radius=2)
        draw_text(self.screen, self.font_sm, f"{self.canvas.width}px", (bx+bw-14, y+26))

        # Кнопки справа
        btns = [
            ("Cmd+Z Отмена",   UI_TEXT),
            ("Cmd+C Очистить", (255, 100, 80)),
            ("Cmd+S Сохранить", UI_ACCENT),
            ("H Камера", UI_SUCCESS if self.show_camera else STATUS_IDLE),
        ]
        rx = WINDOW_W - PAD
        for label, col in reversed(btns):
            tw = text_w(self.font_sm, label) + 16
            rx -= (tw + 6)
            draw_panel(self.screen, (rx, y, tw, 46))
            draw_text(self.screen, self.font_sm, label, (rx+8, y+16), color=col)

    def _draw_bottom(self):
        PAD = 14
        gy  = WINDOW_H - 58

        guide = [("☝", "РИСОВАТЬ"), ("✌", "Смена цвета"),
                 ("✋", "Очистить"), ("✊", "Пауза")]

        gw = sum(max(text_w(self.font_md, e), text_w(self.font_sm, l)) + 16
                 for e, l in guide) + PAD * 2
        draw_panel(self.screen, (PAD, gy, gw, 46))
        cx = PAD + PAD
        for emoji, label in guide:
            ew = max(text_w(self.font_md, emoji), text_w(self.font_sm, label)) + 16
            draw_text(self.screen, self.font_md, emoji, (cx, gy+4), shadow=False)
            draw_text(self.screen, self.font_sm, label,  (cx, gy+26), color=(160,160,160))
            cx += ew

        # Статус
        smw = text_w(self.font_md, self.status_msg) + 28
        sx  = WINDOW_W - PAD - smw
        draw_panel(self.screen, (sx, gy, smw, 46))
        dot = self.status_color if self.gesture != Gesture.UNKNOWN else STATUS_IDLE
        pygame.draw.circle(self.screen, dot, (sx+14, gy+23), 5)
        draw_text(self.screen, self.font_md, self.status_msg, (sx+24, gy+14), color=self.status_color)

    def _draw_flash(self):
        if not self.flash_msg or time.time() > self.flash_end:
            return
        frac  = min(1.0, (self.flash_end - time.time()) / 0.4)
        alpha = int(255 * frac)
        fw = text_w(self.font_lg, self.flash_msg) + 32
        fh = 52
        fx = (WINDOW_W - fw) // 2
        fy = WINDOW_H // 2 - 80
        s  = pygame.Surface((fw, fh), pygame.SRCALPHA)
        pygame.draw.rect(s, (30, 30, 30, int(200*frac)), (0, 0, fw, fh), border_radius=14)
        self.screen.blit(s, (fx, fy))
        ts, _ = self.font_lg.render(self.flash_msg, (255, 255, 255))
        ts.set_alpha(alpha)
        self.screen.blit(ts, (fx+16, fy+12))

    # ── Сохранение ────────────────────────────────────────────

    def _save(self):
        ts   = time.strftime("%Y%m%d_%H%M%S")
        path = os.path.expanduser(f"~/Desktop/AirDraw_{ts}.png")
        surf = pygame.Surface((WINDOW_W, WINDOW_H))
        surf.fill((0, 0, 0))
        self.canvas.render(surf)
        pygame.image.save(surf, path)
        self._flash(f"Сохранено: AirDraw_{ts}.png", 2.5)


# ─────────────────────────────────────────────────────────────
# Запуск
# ─────────────────────────────────────────────────────────────

def main():
    print("=" * 52)
    print("  AirDraw — Рисование в воздухе")
    print("=" * 52)

    if not os.path.exists(MODEL_PATH):
        print(f"\n✗ Модель не найдена: {MODEL_PATH}")
        print("  Запустите: curl -L https://storage.googleapis.com/mediapipe-models/"
              "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task "
              f"-o \"{MODEL_PATH}\"")
        sys.exit(1)

    print("""
Жесты:
  ☝  Один указательный палец   — РИСОВАТЬ (кисть)
  ✌  V-жест (удержать)         — сменить цвет
  ✋  Открытая ладонь (удержать) — очистить холст
  ✊  Кулак / щипок              — пауза (поднять кисть

Клавиши:
  Cmd+Z — Отмена   Cmd+C — Очистить   Cmd+S — Сохранить
  H — Камера   ↑↓ — Толщина линии   → — Следующий цвет

⚠️  Если камера не работает:
  Системные настройки → Конфиденциальность → Камера
  Разрешите доступ для Терминала (или вашего IDE)
""")

    try:
        app = AirDrawApp()
        app.run()
    except KeyboardInterrupt:
        print("\nЗавершено.")
    except Exception as e:
        import traceback
        print(f"\n✗ Ошибка: {e}")
        traceback.print_exc()


if __name__ == "__main__":
    main()
