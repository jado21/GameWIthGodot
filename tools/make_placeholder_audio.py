import math, random, struct, wave
from pathlib import Path
names = 'step land jump double_jump wall_jump dash slide_start slide_loop wind_loop shot_pistol shot_shotgun shot_rifle empty_click switch_weapon detector_pulse item_ping_weapon item_ping_ammo pickup_weapon pickup_ammo hook_fire hook_release hit_marker player_hurt dodge perfect_dodge slide_kick monster_stomp monster_warn monster_swing monster_lunge monster_throw rock_explode monster_roar monster_roar_big shockwave victory defeat ambient_drone'.split()
out = Path(__file__).parents[1] / 'audio'; out.mkdir(exist_ok=True)
rate=22050
for name in names:
    duration=1.5 if name.endswith('_loop') or name=='ambient_drone' else .24
    frames=[]
    base=100+hash(name)%900
    for i in range(int(rate*duration)):
        t=i/rate; env=max(0,1-t/duration)**2
        tone=math.sin(2*math.pi*(base+(1-t/duration)*base*.35)*t)
        noise=(random.random()*2-1)*.25
        value=max(-1,min(1,(tone*.7+noise)*env*.45))
        frames.append(struct.pack('<h',int(value*32767)))
    with wave.open(str(out/(name+'.wav')),'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate); f.writeframes(b''.join(frames))
