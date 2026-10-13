# 坐标变换

## Clarke变换

![屏幕截图 2026-03-12 202744](E:\desktop\FOC\FOC.assets\屏幕截图 2026-03-12 202744.png)

将三相电分解到直接坐标系

## Park变换

![image-20260312203120866](./FOC.assets/image-20260312203120866.png)

# SVPWM

![image-20260313105132023](./FOC.assets/image-20260313105132023.png)

对三组MOS管进行编码，当上方为开，下方为关则为1，上方为关，下方为开则为0。

当编码为000或111时，无电流流过，当其中任意一个为1时，则为流入

## 相电流与线电流的转化

![image-20260313105422578](./FOC.assets/image-20260313105422578.png)

## 任意磁场的合成 ——平均值等效原理

![image-20260313110003991](./FOC.assets/image-20260313110003991.png)

对于一个合成的磁场矢量，若总控制周期是3ms，其中Ux作用1ms，Uy作用1ms，U0作用1ms，则合成的矢量就是30度，大小比满作用的时候小。

所以**Ux和Uy决定磁场的方向，U0决定磁场的强度**

![image-20260313110452818](./FOC.assets/image-20260313110452818.png)

![image-20260313110615975](./FOC.assets/image-20260313110615975.png)

​                                     							**这里由正弦定理得到Uout**

## 软件模式的MOS开关——七段式

![image-20260313111221830](./FOC.assets/image-20260313111221830.png)

调整开关和作用时间

## 硬件模式的MOS开关——五段式

![image-20260313111311635](./FOC.assets/image-20260313111311635.png)

## 扇区的判断

![image-20260313194813117](./FOC.assets/image-20260313194813117.png)

扇区的判断只由Ua和Ub的大小即可判断，关系上如图所示，要算出Uref123，得到N，再对比图表关系

**此外，如果知道Uout的角度也可以通过下面的方法判断**

![image-20260313195140212](./FOC.assets/image-20260313195140212.png)

## 零矢量和非零矢量的计算

![image-20260313204217151](./FOC.assets/image-20260313204217151.png)

这里的N = 1并不是第一扇区的意思

而且这里的U4和U6实际是Ux和Uy，不要搞错

![image-20260418221736584](./FOC.assets/image-20260418221736584.png)

## 扇区切换点的确定

![image-20260313204517159](./FOC.assets/image-20260313204517159.png)

# VESC

## 核心算法

![image-20260414163601739](./FOC.assets/image-20260414163601739.png)

### 1. 参数离线自辨识

VESC实现了全自动参数辨识。电阻测量用直流注入法，给定电流看稳态电压。电感测量用高频方波注入，测电压斜率算di/dt。磁链测量靠开环旋转，测反电势峰值。凸极率测量用多角度扫频，对比不同方向的电流响应。

加上编码器矫正，整个流程3分钟跑完，精度±5%。测完后参数自动写入配置，直接能用。不需要拆电机，不需要示波器，上位机点个按钮就行。

这个功能对快速调试帮助很大。换个电机，跑一遍辨识，PI参数自动整定好。比手动测参数效率高太多。

### 2. 七种观测器算法

无感控制的核心是位置观测器。VESC支持7种算法，运行时可切换。

经典的Ortega算法，基于反电势磁链积分。MxLemming算法是MESC项目贡献的优化版，低速稳定性更好。MxV系列有3个变种，分别针对不同的电机参数。还有带λ补偿的版本，处理磁路饱和。

不同算法适用场景不一样。低速用MxLemming，高速用Ortega精度高。永磁同步电机和内置式电机选择也不同。代码里都实现了，配置文件切换就行。

观测器的数学原理其实不复杂，就是状态方程加误差校正。但工程实现有很多坑。磁链幅值要限幅，否则积分器会发散。电阻温度漂移要补偿，不然角度误差累积。采样噪声要滤波，但滤波器又引入相位滞后。

### 3. HFI高频注入

VESC支持3种HFI ambiguity模式（`mc_foc_hfi_amb_mode`）：

- **SIX_VECTOR**：6向量模式，旋转注入，鲁棒性好但计算量大
- **D_SINGLE_PULSE**：d轴单脉冲注入
- **D_DOUBLE_PULSE**：d轴双脉冲注入

另外有5种HFI传感器模式变体（FOC_SENSOR_MODE_HFI / HFI_V2 / HFI_V3 / HFI_V4 / HFI_V5），对应不同的算法优化版本。

在极性判断中。d轴有两个方向，N极和S极。单纯的高频注入只能确定轴线，分不清极性。VESC在启动前累积128个样本，旋转注入方向，统计哪个方向电流响应更大。这个方向就是N极。整个过程4-5毫秒。

HFI只在低速用。加速到1500 ERPM后，反电势够大了，自动切换到观测器模式。切换过程做了平滑处理，角度不会跳变。



### 4. 温度自适应

铜线电阻温度系数0.39%/°C。电机从25°C跑到80°C，电阻涨21%。

电阻变了，PI参数不跟着调就会出问题。积分时间常数Ti = L/R，R变大Ti变小，电流环动态特性偏移。解耦补偿的前馈项也用R，R不准解耦效果就差。观测器的电压方程里有R·i项，R偏了磁链估算就错，角度误差累积。

VESC每1ms读一次电机温度，NTC热敏电阻采样。温度通过B值方程换算成开尔文，然后用线性模型修正电阻：R(T) = R0 × (1 + α(T - T0))。修正后的R用在解耦补偿和观测器里。

还有个细节，Ki也要跟着调。电阻变了，极点位置变了，保持相同的闭环特性需要动态调整Ki。代码里实现了这个补偿，冷启动和热态的控制性能基本一致。

除了温度，磁路饱和也要补偿。大电流时磁路饱和，磁链λ会下降。VESC根据电流幅值动态调整λ的估计值，保证观测器在全电流范围内都准确。

![image-20260414163823973](./FOC.assets/image-20260414163823973.png)![image-20260414163841549](./FOC.assets/image-20260414163841549.png)

### 7. 智能电流采样

VESC定义了4种电流采样模式（`mc_foc_current_sample_mode`），但实际只能用3种：

**1. LONGEST_ZERO（最长零矢量）**：选择PWM占空比最低的相，对应零矢量最长的时刻采样。只采两相，第三相用KCL计算（ia+ib+ic=0）。

**2. ALL_SENSORS（完整Clarke）**：三相都采样，完整Clarke变换。精度最高，要求占空比在合理范围。

**3. HIGH_CURRENT（高电流模式）**：选电流幅值最大的相计算（用其他两相推算），扩大电流测量范围。

**4. BEST_SENSOR（最佳传感器）**：实验性功能，代码中被`#if 0`注释掉，未实际使用。

实际应用中主要用前两种模式。代码根据PWM占空比和硬件配置（是否有相分流器`HW_HAS_PHASE_SHUNTS`）自动切换。

代码里每个周期判断当前占空比，选择合适的模式。切换是无缝的，不会产生电流跳变。



### 8. SVPWM扇区优化

SVPWM每个控制周期都要算一次三相占空比。VESC的实现做了几处优化：

**预计算常数**：扇区判断需要比较β和α/√3的关系。代码定义了`ONE_BY_SQRT3 = 0.577`，把除法变成乘法。

**整数化运算**：矢量时间乘以PWM周期后立即转int，后续全用整数加减，不用浮点。

**公式化简**：每个扇区的占空比计算公式都化简过。以扇区1为例：

```text
int t1 = (alpha - ONE_BY_SQRT3 * beta) * PWMFullDutyCycle;
int t2 = (TWO_BY_SQRT3 * beta) * PWMFullDutyCycle;
tA = (PWMFullDutyCycle + t1 + t2) / 2;
tB = tA - t1;
tC = tB - t2;
```

只需要2次浮点乘法，1次整数除2，2次整数减法。零矢量时间t0隐含在公式里，不用单独算。

**七段式SVPWM**：零矢量平均分配到周期两端，开关次数最少，谐波最低。



### 9. 双电机同步控制

硬件支持两个电机。TIM1管电机1，TIM8管电机2。两个定时器配置相同，可以独立控制，也可以同步控制。

同步控制通过CAN总线实现。一个控制器做主机，发送时间戳和目标值。其他控制器做从机，接收时间戳同步自己的动作。时间戳误差可以控制在1ms以内。

应用场景很多。四轮驱动的电动车，四个电机要协同输出扭矩。双电机云台，两个电机要同步转动保持平衡。机器人多关节，各个关节要配合完成动作。

CAN总线的带宽是个限制。1Mbps的速率，发送一帧扩展帧大约100微秒。如果同步频率太高，CAN总线会占满。VESC的做法是低频同步（100Hz），高频控制各自独立。



### 10. 多层故障保护

VESC的故障保护做了多层设计。

**硬件层**：比较器监测相电流，超过阈值（比如150A）立即触发TIM1的刹车输入，硬件关断PWM输出。响应时间小于500纳秒，MOSFET来不及烧毁。

**软件层**：ADC中断里检测电流，超过软件限流值（比如120A）立即切换到刹车模式。响应时间是一个控制周期，33微秒。

**热保护**：定时器线程读取温度，MOSFET温度超过100°C限流50%，超过120°C停机。电机温度超过设定值也限流或停机。

**通信超时**：500ms没收到上位机指令，自动刹车停机。防止通信断开后电机失控。

**配置保护**：Flash存储的配置带CRC32校验。读配置时先验证CRC，损坏了就加载上一个备份。写配置时用磨损均衡，选择擦写次数最少的扇区。

这些保护机制让VESC在各种异常情况下都能安全关断，不会烧硬件。实际应用中碰到过几次堵转和过流，硬件保护直接切断输出，板子完好无损。



## 控制流程与优化

![img](https://pic4.zhimg.com/v2-3cdb677355d7e3f3ff0993612e4012f9_1440w.jpg)

### 一、ADC中断和电流采样

VESC的FOC控制频率默认是25kHz，也就是每40微秒执行一次控制循环。这个频率是怎么来的？

[STM32F405](https://zhida.zhihu.com/search?content_id=267696118&content_type=Article&match_order=1&q=STM32F405&zhida_source=entity)的系统时钟是168MHz，通过设置[PWM定时器](https://zhida.zhihu.com/search?content_id=267696118&content_type=Article&match_order=1&q=PWM定时器&zhida_source=entity)TIM1的ARR寄存器决定PWM周期：

```text
uint32_t top = SYSTEM_CORE_CLOCK / (int)configuration->foc_f_zv;
// 168000000 / 25000 = 6720
TIM1->ARR = top;
```

PWM计数器从0数到6720，然后复位，触发ADC采样中断。这就是控制周期的起点。

（关于如何选取PWM控制频率，我们应该结合板载对应主控的时钟频率、算法所对应计算时间、项目其他文件运行时间，以及各元器件来综合判定，**频率太低**：电流纹波大，控制带宽受限，**频率太高**：开关损耗大，留给MCU的计算时间少）

ADC中断触发后，首先要读取三相电流。理想情况下，我们希望在零矢量期间采样——此时三个下桥臂都导通，电流路径稳定，采样值最准确。

问题是：**占空比极端时，零矢量时间可能不够ADC完成转换**。

ADC转换一次需要大约900个定时器计数周期（约5.4微秒）。当PWM占空比很大或很小时，零矢量窗口会被压缩。举个例子：**占空比90%时**：高电平5400计数，低电平（零矢量）只有1320计数，此时1320 < 900，ADC来不及采样。

VESC的解决方案是定义一个阈值：

```text
#define SHUNT_PICK_THR 900
```

计算一下临界点：900 / 6720 = **13.4%**

也就是说：

- **占空比 < 13.4% 或 > 86.6%时，切换到备用策略**
- **正常范围内，使用标准策略**

VESC支持两种[电流采样模式](https://zhida.zhihu.com/search?content_id=267696118&content_type=Article&match_order=1&q=电流采样模式&zhida_source=entity)：

**模式1：HIGH_CURRENT（大电流模式）**

- 这个模式的思路是：三相加起来等于零，那就找出电流绝对值最大的那相，不直接测它，用另外两相的实测值算出来（这是**三电阻采样的优势所在，能避免直接测量最大或者最小的那一相电流，从而减少电流采样误差**）。
- 代码逻辑：

```text
if (conf_now->foc_current_sample_mode == FOC_CURRENT_SAMPLE_MODE_HIGH_CURRENT) {
    full_clarke = false;
    
    const float i0_abs = fabsf(curr0);
    const float i1_abs = fabsf(curr1);
    const float i2_abs = fabsf(curr2);
    
    if (i0_abs > i1_abs && i0_abs > i2_abs) {
        curr0 = -(curr1 + curr2);  // A相电流最大，用B、C相推算
    }
    // ... 其他相类似
}
```

比如A相电流100A，B相-40A，C相-60A，如果A相采样窗口不够，就只测B和C，然后算出A = -(B+C) = -(-40-60) = 100A。虽然A相是推算的，但误差不大。

**LONGEST_ZERO模式**（正常工况） 占空比在合理范围内时，三相都能**直接测**。但还是要判断零矢量窗口够不够：

```text
else if (conf_now->foc_current_sample_mode == FOC_CURRENT_SAMPLE_MODE_LONGEST_ZERO) {
    if (is_v7) {  // V7零矢量期间
        if (tim->CCR1 < SHUNT_PICK_THR ||
            tim->CCR2 < SHUNT_PICK_THR ||
            tim->CCR3 < SHUNT_PICK_THR) {
            full_clarke = false;  // 窗口不够，切换到简化Clarke
            // ... 选合适的相采样
        }
    }
}
```

这里的`is_v7`判断的是当前在V0还是V7零矢量（[SVPWM](https://zhida.zhihu.com/search?content_id=267696118&content_type=Article&match_order=1&q=SVPWM&zhida_source=entity)的两个零状态）。代码会在V7期间检查三个相的占空比，任何一相的窗口<900就触发简化策略。

关键在于`full_clarke`这个标志位——它决定了后面[Clarke变换](https://zhida.zhihu.com/search?content_id=267696118&content_type=Article&match_order=1&q=Clarke变换&zhida_source=entity)用完整公式还是简化公式。整个切换过程在中断里自动完成，电机运行不会有感知。

**思考**：为什么不一直用简化Clarke？

虽然简化Clarke计算量小，但它依赖ia+ib+ic=0这个假设。实际硬件中：

- ADC有偏差
- 采样时刻略有差异
- 电流可能不完全平衡

三相都测能**互相校验**，精度更高。只在不得已时才切换到简化模式——这是非常值得借鉴的电流采样思路：优先保证精度，实在不行再牺牲。

### 二、Clarke变换

变换完成后得到i_alpha和i_beta，存到motor_state_t结构体里往下传。坐标系从三相ABC变成了两相αβ，但电流信息没丢。

为什么降维不会丢信息？

关键在于**三相对称系统的约束**：ia + ib + ic = 0

这个约束来自基尔霍夫电流定律——电机中性点没有引出，三相电流必然相加为零。所以三个量里只有两个自由度，第三个是冗余的。Clarke变换就是去掉这个冗余。

就好像三维空间里的一个平面（z = 0），本质上只需要x和y两个坐标就能完全描述。

#### 两个公式

根据前面`full_clarke`标志位的不同，代码走两条路：

**完整Clarke**（三个电流都测了）：

```text
if (full_clarke) {
    state_now->i_alpha = (2.0 / 3.0) * ia - (1.0 / 3.0) * ib - (1.0 / 3.0) * ic;
    state_now->i_beta = ONE_BY_SQRT3 * ib - ONE_BY_SQRT3 * ic;
}
```

**简化Clarke**（假设三相平衡）：

```text
else {
    state_now->i_alpha = ia;
    state_now->i_beta = ONE_BY_SQRT3 * ia + TWO_BY_SQRT3 * ib;
}
```

第二个公式是把ia + ib + ic = 0代入第一个公式推出来的。数学上等价，但计算量更小。



### 2.2 预计算常数

注意代码里没有写`1.0 / sqrt(3.0)`这种，而是直接用了预定义常数：

```text
#define ONE_BY_SQRT3  (0.57735026919)
#define TWO_BY_SQRT3  (2.0f * 0.57735026919)
```

ARM Cortex-M4的浮点除法大概要14个时钟周期，乘法只要3-5个。预先算好常数后，所有除法都变成了乘法。40微秒的控制周期里，这种小优化积累起来效果明显。

**思考**：预计算常数到底省了多少时间？

ARM Cortex-M4的性能数据：

- 浮点除法：~14个时钟周期
- 浮点乘法：~3个时钟周期

Clarke变换里有3次除以√3的操作，预计算后：

- 节省时间：(14-3) × 3 = 33个时钟周期
- 占比：33 / 6720 ≈ 0.5%

看起来不多，但整个控制循环有十几个这样的优化，累加起来能省10%-15%的时间。工程优化其实就是这样积少成多的过程。





### 三、[Park变换](https://zhida.zhihu.com/search?content_id=267696118&content_type=Article&match_order=1&q=Park变换&zhida_source=entity)

#### 3.1 为什么要旋转坐标系

现在电流在αβ坐标系里了，但这个坐标系是静止的。转子在转，所以αβ坐标系里看到的电流是正弦波。[PI控制器](https://zhida.zhihu.com/search?content_id=267696118&content_type=Article&match_order=1&q=PI控制器&zhida_source=entity)不适合控制正弦量。

Park变换就是把坐标系转起来，让它跟着转子同步旋转。这样在旋转坐标系（dq坐标系）里看，电流就变成直流了。

把这个比喻记住：

- **静止坐标系（αβ）**：你站在地上看旋转木马，看到的是一圈圈转动
- **旋转坐标系（dq）**：你坐在旋转木马上，相对你来说周围是静止的

PI控制器设计时假设被控对象是直流量。在αβ坐标系里电流是正弦波（交流量），PI控制器会有稳态误差。在dq坐标系里电流是直流量，PI控制器能做到零稳态误差。

这就是Park变换的价值：**把时变问题转换成时不变问题**。



#### 3.2 角度从哪来

Park变换需要知道转子当前角度θ。根据传感器模式不同：

- 编码器模式：直接读编码器
- 霍尔模式：插值算
- 无感模式：观测器估计（下期讲）

但代码里不是现算sin(θ)和cos(θ)，而是直接用现成的值：

```text
float s = state_m->phase_sin;
float c = state_m->phase_cos;

state_m->id = c * state_m->i_alpha + s * state_m->i_beta;
state_m->iq = c * state_m->i_beta - s * state_m->i_alpha;
```

这两个值是上一个控制周期算好的（或者观测器更新的）。即使用了快速三角函数（上期讲的多项式近似），也比直接用现成值慢。实时控制里能省就省。

**思考**：为什么不每次都算sin/cos？

即使用快速三角函数（多项式近似），计算sin和cos也要几十个时钟周期。而直接用已经算好的值，只是两次内存读取，几个时钟周期就够了。

更深层原因：**时序解耦**。

- 转子角度更新：可能在编码器中断、观测器线程里
- 电流控制循环：在ADC中断里
- 两者频率可能不同（比如编码器更新可能比电流环快）

把角度计算和Park变换解耦，各自在合适的地方执行，整体架构更清晰。

#### 3.3 dq轴的物理意义

变换完得到两个电流：

- **id**：沿着转子磁场方向的电流。控制磁场强度，弱磁时给负id削弱磁场，提高最高转速。
- **iq**：垂直于磁场的电流。直接产生转矩，iq越大力矩越大。

在dq坐标系里，稳态时id和iq都是直流量，使得PI控制器能够有很好的控制效果。

代码还做了个滤波：

```text
UTILS_LP_FAST(state_m->id_filter, state_m->id, conf_now->foc_current_filter_const);
UTILS_LP_FAST(state_m->iq_filter, state_m->iq, conf_now->foc_current_filter_const);
```

**⭐滤波后的值不用于反馈控制（会引入延迟），而是给解耦补偿等不那么时间敏感的地方用**。



### 四、PI电流控制

#### 4.1 双轴PI控制器

现在有了实际电流id和iq，跟目标值一比：

```text
float Ierr_d = state_m->id_target - state_m->id;
float Ierr_q = state_m->iq_target - state_m->iq;
```

然后对每个轴跑PI控制器：

```text
float ki = conf_now->foc_current_ki;
if (conf_now->foc_temp_comp) {
    ki = motor->m_current_ki_temp_comp;  // 温度补偿
}

state_m->vd_int += Ierr_d * ki * dt;  // 积分项
state_m->vq_int += Ierr_q * ki * dt;

state_m->vd = state_m->vd_int + Ierr_d * conf_now->foc_current_kp;  // P+I
state_m->vq = state_m->vq_int + Ierr_q * conf_now->foc_current_kp;
```

标准的PI：比例项快速响应，积分项消除稳态误差。代码注释里还解释了为什么不加D：

**工程思考**：为什么不加D项？

代码注释里写得很清楚：

```text
// No D action needed because the plant is a first order system
```

电机电流环的传递函数是：I(s) / V(s) = 1 / (Ls + R)，典型一阶系统。

一阶系统用PI就够了：

- P项：快速响应
- I项：消除稳态误差
- D项：预测未来变化趋势

但一阶系统没有超调倾向（不像二阶系统），加D项是多此一举，而且会放大高频噪声。

这是控制理论的基本原则：**根据被控对象的阶数选择控制器**。不是所有场合都需要PID三个项。

```text
// No D action needed because the plant is a first order system (tf = 1/(Ls+R))
```

**电机电流环本身就是一阶系统，加微分项没必要，反而会放大噪声**。

#### 4.2 温度补偿ki

铜线电阻随温度升高而增大，温度系数约0.386%/°C。电机热了之后，同样电压产生的电流会变小。如果ki固定，控制器会发现误差增大，拼命提高电压，最后可能超调。

VESC的做法是**根据温度调整ki**：

```text
float comp_fact = conf->foc_temp_comp_base_temp - motor_temp;
comp_fact *= 0.00386;  // 铜的温度系数
comp_fact += 1.0;

motor->m_current_ki_temp_comp = conf->foc_current_ki * comp_fact;
```

基准温度和实际温度差多少度，ki就按比例调整。电机温度变化时控制性能能保持一致。

**实践要点**： 温度补偿不是必须的，但有了它系统鲁棒性会好很多：

- 冷机启动 vs 热机运行，性能一致
- 环境温度变化（冬天vs夏天），参数不用重调

VESC的实现很巧妙：只补偿ki，不补偿kp。为什么？

- ki直接和电阻相关（积分项消除稳态误差，稳态时主要对抗电阻）
- kp主要和电感相关（快速响应，主要对抗电感的惯性）
- 电感随温度变化很小，不用补偿

#### 4.3 电压饱和和圆形限幅

PI算出来的vd和vq可能很大，但实际能输出的电压有限——受母线电压限制。

代码先算最大电压幅值：

```text
float max_v_mag = ONE_BY_SQRT3 * max_duty * state_m->v_bus * conf_now->foc_overmod_factor;
```

`ONE_BY_SQRT3`（0.577）倍是SVPWM的理论极限——不过调制时，空间矢量调制最多能用到母线电压的1/√3。

然后饱和处理：

```text
// d轴优先
utils_truncate_number_abs((float*)&state_m->vd, max_v_mag);
utils_truncate_number_abs((float*)&state_m->vd_int, max_v_mag);

// q轴用剩余电压
float max_vq = sqrtf(SQ(max_v_mag) - SQ(state_m->vd));
utils_truncate_number_abs((float*)&state_m->vq, max_vq);
utils_truncate_number_abs((float*)&state_m->vq_int, max_vq);
```

d轴优先限幅（控制弱磁和效率更重要），然后q轴用圆形限幅：vd² + vq² ≤ max_v_mag²。

关键是积分项也要同步限幅。如果不限制积分项，电压饱和时积分会继续累积，等饱和解除后系统反应会很慢（积分饱和问题）。

**理解要点**：为什么d轴优先？

两个原因：

1. **弱磁控制**：高速时需要负的id削弱磁场，这是突破电压限制的唯一方法。如果vd被限制住，弱磁失效，电机到不了最高转速
2. **效率优化**：id影响铁损和铜损的平衡，优先保证效率

q轴虽然直接产生转矩，但如果电压不够，大不了转矩小一点。d轴如果不够，整个弱磁策略就崩了。

**调试技巧**： 如果发现电机高速时转速上不去，检查：

1. vd是否达到饱和（说明母线电压不够）
2. 弱磁电流限制是否太小（`foc_fw_current_max`参数）
3. 观察vd和vq的轨迹，应该在一个圆内，如果贴着圆边说明饱和了

### 五、解耦补偿：提前抵消耦合

#### 5.1 dq轴其实不独立

理想情况下d和q两个轴应该是独立的，控制id不影响vq。但从dq轴电压方程我们可以看出它们是耦合的：

```text
vd = R*id + Ld*(did/dt) - ωe*Lq*iq      // 注意最后这项
vq = R*iq + Lq*(diq/dt) + ωe*Ld*id + ωe*ψm
```

代码注释里直接把公式写出来了：

```text
// vd = Rs*id + Ld*did/dt − ωe*iq*Lq
// vq = Rs*iq + Lq*diq/dt + ωe*id*Ld + ωe*ψm
```

iq的变化会影响vd（交叉项 -ωe*Lq*iq），id的变化会影响vq（交叉项 +ωe*Ld*id）。转速ωe越高，耦合越强。还有个反电势项ωe*ψm，转速高了需要的vq也大。

不处理这些耦合，PI控制器就得追着误差跑，响应变慢。

**深度分析**：耦合到底有多大影响？

定量算一下。假设电机参数：

- Ld = Lq = 0.1mH
- iq = 100A
- 转速 = 3000rpm（电角速度约314 rad/s）

交叉项大小：

- ωe × Lq × iq = 314 × 0.0001 × 100 = **3.14V**

如果母线电压48V，这个耦合项占比：3.14 / 48 ≈ **6.5%**

低速时占比小，可以不补偿。**高速时占比大，不补偿的话电流环响应会明显变慢**。

#### 5.2 前馈补偿

既然知道有干扰，就提前算出来加上去抵消。代码支持三种模式：

```text
switch (conf_now->foc_cc_decoupling) {
case FOC_CC_DECOUPLING_CROSS:
    // 只补偿交叉项
    dec_vd = state_m->iq_filter * motor->m_speed_est_fast * motor->p_lq;
    dec_vq = state_m->id_filter * motor->m_speed_est_fast * motor->p_ld;
    break;

case FOC_CC_DECOUPLING_BEMF:
    // 只补偿反电势
    dec_bemf = motor->m_speed_est_fast * conf_now->foc_motor_flux_linkage;
    break;

case FOC_CC_DECOUPLING_CROSS_BEMF:
    // 都补偿
    dec_vd = state_m->iq_filter * motor->m_speed_est_fast * motor->p_lq;
    dec_vq = state_m->id_filter * motor->m_speed_est_fast * motor->p_ld;
    dec_bemf = motor->m_speed_est_fast * conf_now->foc_motor_flux_linkage;
    break;
}

state_m->vd -= dec_vd;  // 注意符号
state_m->vq += dec_vq + dec_bemf;
```

`m_speed_est_fast`就是电角速度ωe（单位rad/s），`p_ld`和`p_lq`是d轴和q轴电感。公式跟PMSM方程完全对应。

注意**用的是滤波后的电流`id_filter`和`iq_filter`**。实时电流有噪声，直接用会导致补偿量抖动。滤波值平滑，补偿更稳定。这又是个工程权衡：理论上该用瞬时值，实际用滤波值更可靠。

**工程思考**：为什么要分三种模式？

| 模式       | 计算量 | 效果     | 适用场景         |
| ---------- | ------ | -------- | ---------------- |
| DISABLED   | 0      | 无补偿   | 低速应用         |
| CROSS      | 中     | 改善动态 | 高速应用         |
| BEMF       | 低     | 提高效率 | 中速应用         |
| CROSS_BEMF | 高     | 最佳效果 | 性能要求高的场景 |

不同应用对性能和计算资源的需求不同，VESC给了选择权，这一点在我们自己设计的时候同样可以借鉴。

**学习建议**： 想深入理解解耦的话，建议：

1. 先不开解耦补偿，用示波器看id和iq的阶跃响应
2. 逐个打开CROSS、BEMF、CROSS_BEMF，对比响应速度
3. 观察高速时的差异（低速时可能看不出来）

### 六、逆Park变换

#### 6.1 为什么要变回去

vd和vq算好了，但**SVPWM工作在αβ坐标系（静止坐标系）**。所以得把dq电压转回αβ。

但在此之前先做了归一化：

```text
const float voltage_normalize = 1.5 / state_m->v_bus;
state_m->mod_d = state_m->vd * voltage_normalize;
state_m->mod_q = state_m->vq * voltage_normalize;
```

SVPWM需要的不是绝对电压（单位伏特），而是调制度（无量纲，-1到1）。

为什么系数是1.5？代码注释解释了：

```text
// voltage_normalize = 1/(2/3*V_bus)
```

SVPWM的电压利用率是2/3 * V_bus（相电压有效值），倒数就是1.5。这样归一化后，mod_d和mod_q的物理意义是：相对于最大可用电压的比例。

#### 6.2 逆变换

归一化后做逆Park变换：

```text
state_m->mod_alpha_raw = c * state_m->mod_d - s * state_m->mod_q;
state_m->mod_beta_raw  = c * state_m->mod_q + s * state_m->mod_d;
```

还是用那两个预先算好的sin和cos。把旋转坐标系转回静止坐标系，得到αβ轴的调制度，传给SVPWM。

**理解要点**：为什么要归一化？

SVPWM算法的输入是**调制度**（0-1之间），不是绝对电压（伏特）。

原因：

1. 母线电压会波动（刹车时上升，加速时下降）
2. SVPWM算法不关心绝对值，只关心三相电压的相对比例
3. 归一化后，同一套SVPWM代码适用于任何母线电压

工程思想：**把变化的量归一化，算法只处理不变的部分**

### 七、SVPWM：从αβ到三相占空比

#### 7.1 扇区判断

SVPWM第一步是判断电压矢量在哪个扇区（六个扇区）。代码用的是传统if-else：

```text
if (beta >= 0.0f) {
    if (alpha >= 0.0f) {
        if (ONE_BY_SQRT3 * beta > alpha) {
            sector = 2;
        } else {
            sector = 1;
        }
    } else {
        // ... 扇区3或2
    }
} else {
    // ... 扇区4/5/6
}
```

为什么不用查表或者位运算优化？因为这样最直观，而且现代CPU有分支预测，if-else其实不慢。稳定运行时扇区变化有规律，分支预测命中率很高。

#### 7.2 矢量时间计算

确定扇区后算两个基本矢量的作用时间：

```text
int t1 = (alpha - ONE_BY_SQRT3 * beta) * PWMFullDutyCycle;
int t2 = (TWO_BY_SQRT3 * beta) * PWMFullDutyCycle;
```

两个优化点：

1. 预计算常数`ONE_BY_SQRT3`和`TWO_BY_SQRT3`，避免除法
2. **浮点乘完立即转int**，后续全用整数运算

为什么要转整数？因为整数加减法1个时钟周期，浮点加减法3-5个。而且占空比最后要写到定时器寄存器，本来就是整数。

#### 7.3 占空比计算

标准SVPWM算法通常这样：

```text
t0 = T - t1 - t2
tA = t1 + t2 + t0/2
tB = t2 + t0/2
tC = t0/2
```

VESC做了公式化简（以扇区1为例）：

```text
*tAout = (PWMFullDutyCycle + t1 + t2) / 2;
*tBout = *tAout - t1;
*tCout = *tBout - t2;
```

把t0代入展开后发现跟标准公式等价，但省掉了中间变量。而且除以2会被编译器优化成右移1位，速度很快。

六个扇区的公式相序不同，但思路一样，用switch-case处理。整个SVPWM计算：扇区判断约10个时钟周期，矢量时间约20个，占空比约3个，总共30-40个时钟周期。在168MHz的CPU上不到1微秒，占控制周期40微秒的比例很小。

**工程思考**：为什么不用查表法？

有些FOC实现用查表法实现SVPWM：

- 预先计算好各个角度的占空比
- 运行时直接查表

VESC没这么做，而是实时计算。原因：

**灵活性**：可以动态调整过调制系数（`foc_overmod_factor`）

**精度**：计算结果是连续的，查表有量化误差

**内存**：查表需要几KB ROM，实时计算只需几十字节代码

而且VESC的SVPWM优化得很好，实时计算也只要30-40个时钟周期，没必要查表。

**学习建议**： SVPWM是FOC的难点之一。理解它的建议路径：

1. 先理解正弦PWM（SPWM）：简单但电压利用率低
2. 再理解空间矢量的概念：八个基本矢量，六个扇区
3. 最后理解矢量合成：用相邻两个基本矢量合成任意矢量
4. 推荐TI的Application Note：SPRU485（写得非常清楚）

别一上来就啃公式，从几何入手更容易理解。



### 八、死区补偿和PWM输出

#### 8.1 死区的必要性

上下桥臂不能同时导通，否则电源直接短路到地，MOSFET烧穿。所以驱动芯片会插入死区时间，确保一个管子关断后另一个才能开。

VESC的硬件死区360ns：

```text
#define HW_DEAD_TIME_NSEC  360.0
```

#### 8.2 死区的副作用

死区时间内上下桥臂都关闭，电流通过续流二极管。这导致实际电压和理想电压有偏差，方向取决于电流方向：

- 电流正向（流入电机）：实际电压偏低
- 电流反向（流出电机）：实际电压偏高

低速时这个误差占比大，会导致转矩脉动和电流畸变。

#### 8.3 补偿算法

VESC的策略是**根据电流方向判断误差方向，然后修正占空比**。

首先把dq轴滤波电流逆变换回三相：

```text
const float i_alpha_filter = c * state_m->id_filter - s * state_m->iq_filter;
const float i_beta_filter = c * state_m->iq_filter + s * state_m->id_filter;

const float ia_filter = i_alpha_filter;
const float ib_filter = -0.5 * i_alpha_filter + SQRT3_BY_2 * i_beta_filter;
const float ic_filter = -0.5 * i_alpha_filter - SQRT3_BY_2 * i_beta_filter;
```

然后提取电流符号（+1或-1），转换到αβ坐标系：

```text
const float mod_alpha_filter_sgn = (1.0/3.0) * (2.0*SIGN(ia_filter) - SIGN(ib_filter) - SIGN(ic_filter));
const float mod_beta_filter_sgn = ONE_BY_SQRT3 * (SIGN(ib_filter) - SIGN(ic_filter));
```

计算补偿量：

```text
const float mod_comp_fact = conf_now->foc_dt_us * 1e-6 * conf_now->foc_f_zv;
const float mod_alpha_comp = mod_alpha_filter_sgn * mod_comp_fact;
const float mod_beta_comp = mod_beta_filter_sgn * mod_comp_fact;

mod_alpha -= mod_alpha_comp;
mod_beta -= mod_beta_comp;
```

`foc_dt_us`是死区时间（微秒），`foc_f_zv`是PWM频率。补偿量就是死区时间占PWM周期的比例，根据电流方向加正或减。

为什么用滤波电流？如果用实时电流，在零点附近噪声会让符号频繁跳变，补偿量抖动。滤波电流平滑，补偿稳定。又是牺牲点实时性换稳定性。

#### 8.4 PWM寄存器更新

最后把占空比写入定时器：

```text
TIM1->CCR1 = duty1;
TIM1->CCR2 = duty2;
TIM1->CCR3 = duty3;
```

由于使能了影子寄存器（Preload），这些值不会立即生效，而是在下个PWM周期开始时自动加载。保证三相同步切换，不会出现"半拍"。

**实践要点**：死区时间怎么测？

代码里配置的360ns可能和实际不一样（驱动芯片、MOSFET特性都有影响）。

实测方法：

1. 用示波器测量上下桥臂的栅极驱动信号
2. 观察上管关断到下管开启的时间间隔
3. 微调`HW_DEAD_TIME_NSEC`参数，直到低速电流波形最平滑

或者直接看效果：给一个小电流指令，看实际电流波形：

- 死区补偿不足：电流波形有毛刺
- 死区补偿过度：电流波形反向畸变
- 补偿刚好：波形平滑

**工程思考**：为什么**用滤波电流判断方向**？

实时电流在零点附近噪声大，符号可能频繁跳变：

```text
实时电流：0.5A → -0.2A → 0.3A → -0.1A（噪声导致）
滤波电流：0.1A → 0.05A → 0.0A → -0.05A（平滑过渡）
```

如果用实时电流，死区补偿方向会跳变，导致占空比抖动，反而增加谐波。用滤波电流虽然有延迟（几个控制周期），但稳定得多。

工程权衡：**牺牲一点实时性，换取稳定性**。

至此，一个完整的FOC控制周期结束。PWM定时器继续计数，下次溢出时ADC中断再次触发，新周期开始





### 九、总结：从时间预算看优化价值

我们跟随了一个完整的控制周期。做个时间分配估算：

| 步骤       | 时钟周期 | 占比  | 优化手段               |
| ---------- | -------- | ----- | ---------------------- |
| ADC采样    | ~200     | 3%    | 硬件触发，并行执行     |
| Clarke变换 | ~30      | 0.4%  | 预计算常数，条件切换   |
| Park变换   | ~15      | 0.2%  | sin/cos预计算          |
| PI控制     | ~100     | 1.5%  | 温度补偿只在需要时计算 |
| 解耦补偿   | ~50      | 0.7%  | 可选模式               |
| 逆Park     | ~15      | 0.2%  | 简单乘法               |
| SVPWM      | ~40      | 0.6%  | 整数运算，公式化简     |
| 死区补偿   | ~80      | 1.2%  | 滤波电流，避免重复计算 |
| 其他逻辑   | ~500     | 7.5%  | 观测器、限流、状态机等 |
| 总计       | ~1030    | 15.3% |                        |
| 剩余裕量   | ~5690    | 84.7% | 留给中断嵌套、其他任务 |

可以看到，核心FOC算法只占了15%的时间预算。大量时间留给了：

- 观测器更新（无感模式计算很耗时）
- HFI高频注入（下期讲）
- 温度监控、故障保护
- 通信协议处理

**关键**：

1. **优化要看整体**：单个函数省几个时钟周期意义不大，关键是系统级优化
2. **留足裕量**：VESC只用了15%时间，留了85%裕量。这是成熟产品的表现——不压榨到极限，留出应对突发情况的空间，裕量足够，才能加新功能（比如双电机控制、CAN通信）





# 电机数学模型的建立

## 基本物理量

![image-20260417122306432](./FOC.assets/image-20260417122306432.png)

## 三相电压动态模型

![image-20260417122352432](./FOC.assets/image-20260417122352432.png)

## 磁链方程分析：转子磁链

![image-20260417122439019](./FOC.assets/image-20260417122439019.png)

**转子的相对磁导率很小，它的位置会影响自感和互感**

## 磁链方程分析：定子磁链

![image-20260417122633409](./FOC.assets/image-20260417122633409.png)

## 坐标变换：CLARKE变换

![image-20260417123039552](./FOC.assets/image-20260417123039552.png)

## 坐标变换：PARK变换

![image-20260417123102171](./FOC.assets/image-20260417123102171.png)

## 坐标变换：ABC->DQ0

![image-20260417123211980](./FOC.assets/image-20260417123211980.png)

## 功率，电磁功率和转矩方程

![image-20260417123311109](./FOC.assets/image-20260417123311109.png)

电磁转矩=电磁功率/机械角速度，**这里的Pn是极对数**

## 运动方程

![image-20260417123430680](./FOC.assets/image-20260417123430680.png)

# PI参数整定

## PMSM数学模型

![image-20260423132718000](./FOC.assets/image-20260423132718000.png)

## 前馈解耦

![image-20260423133633758](./FOC.assets/image-20260423133633758.png)

根据这个式子可以看出id和iq存在交叉项，我们可以解耦

![image-20260423133721092](./FOC.assets/image-20260423133721092.png)

得到等效的Udequ和Uqequ，也就是**通过控制Udequ和Uqequ来线性的控制Id和Iq**

![image-20260423133958162](./FOC.assets/image-20260423133958162.png)

最终得到了解耦后的Ud和Uq

## Id=0下的PI参数整定

在Id = 0的时候，

![image-20260423134110756](./FOC.assets/image-20260423134110756.png)
电磁转矩方程发生退化，**发现电磁转矩Te与Q轴线性相关**

![image-20260423134435485](./FOC.assets/image-20260423134435485.png)

![image-20260423134458545](./FOC.assets/image-20260423134458545.png)

**最终得到了PI参数的整定**

**假定期望电流环带宽为w1，对（9）式进行零极点对消可以得到结果**

![image-20260423134628954](./FOC.assets/image-20260423134628954.png)

![image-20260423134815859](./FOC.assets/image-20260423134815859.png)

## 转速环参数整定

![](./FOC.assets/image-20260423135053787.png)

![image-20260423135539742](./FOC.assets/image-20260423135539742.png)

![image-20260423135652714](./FOC.assets/image-20260423135652714.png)

![image-20260423135722556](./FOC.assets/image-20260423135722556.png)

![image-20260423135755462](./FOC.assets/image-20260423135755462.png)

最后得到了转速环的参数整定

## MTPA下的PI参数整定方案

## 电流环参数

采用前馈解耦的方式，跟Id = 0 的时候一样的参数

## 转速环参数

![image-20260423140254787](./FOC.assets/image-20260423140254787.png)

![](./FOC.assets/image-20260423140354914.png)

![image-20260423140733627](./FOC.assets/image-20260423140733627.png)

![image-20260423140802915](./FOC.assets/image-20260423140802915.png)

![image-20260423140815148](./FOC.assets/image-20260423140815148.png)

![image-20260423140857939](./FOC.assets/image-20260423140857939.png)

## 带宽选取

![image-20260423141012483](./FOC.assets/image-20260423141012483.png)

![image-20260423141025779](./FOC.assets/image-20260423141025779.png)



# 无感控制

## 一、无感控制概念

### 1.1 为什么必须知道转子位置？ 位置误差会导致什么？

![image-20260415213148906](./FOC.assets/image-20260415213148906.png)

这会导致：

**效率下降**：实际输出转矩小于指令值

**转矩脉动**：角度误差随转子位置变化，转矩也跟着变

**电流畸变**：控制器拼命补偿，电流波形变形

举个实际例子：某电机额定转矩2Nm，如果角度误差30°，实际输出转矩只有2× cos(30°)≈ 1.73Nm，损失了13.5%的转矩。而且这个误差会随转子位置周期性变化，导致明显的转矩脉动。

所以角度观测精度直接决定FOC控制系统的性能。工业上要求角度误差 < 5°，高性能应用要求 < 2°。

### 1.2 无感控制的两大物理基础

编码器没有了，但有两个物理现象可以用来推断转子位置：

**物理现象1**：反电势（Back-EMF）

转子旋转时，永磁体切割定子绕组，产生感应电压。这个电压叫反电势，方向永远垂直于磁场方向。

![image-20260415213516192](./FOC.assets/image-20260415213516192.png)

**优点**：

高速时反电势强，信噪比高，不需要特殊电机结构

**缺点**：

反电势正比于转速： **低速时信号弱，噪声淹没静止时反电势为零**，完全失效这就是观测器方法的物理基础，适用于中高速。



**物理现象2**：凸极效应（Saliency）

![image-20260415213754742](./FOC.assets/image-20260415213754742.png)

通过测量**电流响应的方向**，可以推断d轴（也就是转子）的位置。

**优点**：

- **静止时也能工作**（和转速无关）
- 启动时能确定初始位置

**缺点**：

- 需要凸极电机（ 至少要0.7以下效果才会明显）
- 注入高频信号会产生噪声
- 增加损耗（高频电流发热）
- 高速时高频信号被基波淹没

这就是**HFI（高频注入）方法**的物理基础，适用于低速和静止

### 1.3 VESC的多模式策略

<img src="https://picx.zhimg.com/v2-0d9a6bf53427b0bd0dc0fc57c0b013f1_1440w.jpg" alt="img" style="zoom:200%;" />

**关键参数**

（在mcconf_default.h里）：

```text
#define MCCONF_FOC_SL_ERPM_HFI 2000.0  // HFI切换阈值
```

低于这个转速用HFI，高于这个转速用观测器。实际切换有滞后区间，避免来回抖动。

## 二、磁链观测器：从反电势推断位置

### **2.1 观测器的数学模型**

一切从最基本的物理定律开始。

**Step 1：从电压方程出发**

![image-20260415214228601](./FOC.assets/image-20260415214228601.png)

**Step 2：磁链的两个来源**

定子磁链由两部分组成：

![image-20260415214250523](./FOC.assets/image-20260415214250523.png)

**Step 3：反电势的物理本质**

![image-20260415214451650](./FOC.assets/image-20260415214451650.png)

![image-20260415214501187](./FOC.assets/image-20260415214501187.png)

![image-20260415214511591](./FOC.assets/image-20260415214511591.png)

### 2.2 从微分到积分

![image-20260415214655231](./FOC.assets/image-20260415214655231.png)

![image-20260415214704577](./FOC.assets/image-20260415214704577.png)

![image-20260415214711192](./FOC.assets/image-20260415214711192.png)

![image-20260415215702454](./FOC.assets/image-20260415215702454.png)

这就是最简单版本的观测器（***MXV观测器\***）

**小结：**

观测器的核心思路是**用积分代替微分**：

电压方程告诉我们：

对 积分，得到总磁链 

减去电流磁链 ，剩下的就是永磁体磁链 

从永磁体磁链的方向，反推出转子位置 

**为什么要这样做？**

- 避免直接计算 （会放大噪声）
- 积分有平滑作用，对噪声不敏感

![image-20260415215721206](./FOC.assets/image-20260415215721206.png)

### 2.3 稳定性问题和改进：Ortega观测器

#### 问题：积分漂移

纯积分器有个致命问题：**误差累积**（也叫积分漂移）。

**为什么会漂移？**

实际系统中存在各种小误差：

![image-20260423201624944](./FOC.assets/image-20260423201624944.png)

![image-20260423201633590](./FOC.assets/image-20260423201633590.png)

![image-20260423201645996](./FOC.assets/image-20260423201645996.png)

**结果**：X1，X2 可能无限增长或振荡，角度估计完全失效。

**解决思路：加入物理约束**

![image-20260423201730741](./FOC.assets/image-20260423201730741.png)

![image-20260423201742510](./FOC.assets/image-20260423201742510.png)

**VESC代码实现**：

```text
case FOC_OBSERVER_ORTEGA_ORIGINAL: {
    // 计算磁链幅值误差：理论值λ² - 实际值
    float err = SQ(lambda) - (SQ(state->x1 - L_ia) + SQ(state->x2 - L_ib));
    
    // 强制err为负（当err > 0时设为0）
    // 这是论文里的技巧：只在磁链幅值偏大时校正，能加快收敛
    // 物理意义：防止磁链幅值无限增长
    if (err > 0.0) {
        err = 0.0;
    }
    
    // Ortega观测器方程：
    // dx/dt = (v - Ri) + γ/2 * (x - Li) * err
    //         ^^^^^^^^   ^^^^^^^^^^^^^^^^^^^^^
    //         纯积分项      反馈校正项
    float x1_dot = v_alpha - R_ia + gamma_half * (state->x1 - L_ia) * err;
    float x2_dot = v_beta - R_ib + gamma_half * (state->x2 - L_ib) * err;
    
    // 欧拉法离散化
    state->x1 += x1_dot * dt;
    state->x2 += x2_dot * dt;
} break;
```

注意代码里强制 `err` 为负（当 `err > 0` 时设为0）。

**为什么强制 err 为负？**

这是论文中的一个巧妙技巧。从Lyapunov稳定性分析可以知道：

![image-20260423201942101](./FOC.assets/image-20260423201942101.png)

### 2.4 Lyapunov稳定性证明

**控制理论视角：为什么Ortega观测器稳定？**

这部分涉及较多数学推导，**不想看数学的可以跳到下一节**。但如果你想理解为什么观测器能保证收敛，这个证明很重要。

**Step 1：选择Lyapunov函数**

Lyapunov方法的核心思想：找一个”能量函数V” ，证明这个能量随时间递减。

![image-20260423202329340](./FOC.assets/image-20260423202329340.png)

**Step 2：对时间求导**

![image-20260423202339242](./FOC.assets/image-20260423202339242.png)

**Step 3：代入观测器方程**

![image-20260423202350761](./FOC.assets/image-20260423202350761.png)

**Step 4：稳定性结论**

![image-20260423202400639](./FOC.assets/image-20260423202400639.png)

![image-20260423202408484](./FOC.assets/image-20260423202408484.png)

### 2.5 观测器增益的选择

从线性化分析可以得到特征方程（推导省略）：

![image-20260423202424872](./FOC.assets/image-20260423202424872.png)

**1. 基本公式**

![image-20260423202433850](./FOC.assets/image-20260423202433850.png)

**为什么这样设计？**

![image-20260423202447358](./FOC.assets/image-20260423202447358.png)

**2. 带宽要求**

![image-20260423202501572](./FOC.assets/image-20260423202501572.png)

**3. 动态调整（VESC的策略）**

**低速时反电势弱，噪声占比大，应降低增益**：

```text
// 占空比越大，反电势越强，增益可以提高
// utils_map: 线性映射函数
// 输入：当前占空比 fabsf(duty_now)
// 映射范围：[0, 40V/v_bus] -> [0, foc_observer_gain]
// 物理意义：占空比0%时增益为0，占空比达到40V/v_bus时增益为最大值
float gamma_tmp = utils_map(
    fabsf(duty_now),           // 当前占空比（绝对值）
    0.0, 40.0 / v_bus,         // 占空比范围
    0, foc_observer_gain       // 增益范围：0 到最大增益
);

// 低速保护：增益不低于最小值
// foc_observer_gain_slow 默认 0.05 = 5%
// 即使占空比为0，增益也保持在最大值的5%
if (gamma_tmp < (foc_observer_gain_slow * foc_observer_gain)) {
    gamma_tmp = foc_observer_gain_slow * foc_observer_gain;
}

// 参数含义：
// foc_observer_gain：最大增益（高速时），例如 1.2e7
// foc_observer_gain_slow：低速增益缩放系数（默认 0.05 = 5%）
// 低速时实际增益：1.2e7 × 0.05 = 6e5
```

**为什么要动态调整增益？**

这是VESC的一个巧妙设计，平衡了低速稳定性和高速响应性：

![image-20260423202525930](./FOC.assets/image-20260423202525930.png)

### 2.6 MXLEMMING观测器：工程优化版

VESC默认用的不是Ortega，而是**MXLEMMING观测器**（来自MESC项目）。

![image-20260423202544524](./FOC.assets/image-20260423202544524.png)

**核心改进：巧妙处理电流磁链**

![image-20260423202610225](./FOC.assets/image-20260423202610225.png)

**离散化的巧妙之处**：

![image-20260423202622605](./FOC.assets/image-20260423202622605.png)

```text
case FOC_OBSERVER_MXLEMMING:
    // 核心公式：x += (v-Ri)dt - L*Δi
    // 第一项：对(v-Ri)积分，得到总磁链的变化
    // 第二项：减去电流磁链的变化，剩下永磁体磁链
    state->x1 += (v_alpha - R_ia) * dt - L * (i_alpha - state->i_alpha_last);
    state->x2 += (v_beta - R_ib) * dt - L * (i_beta - state->i_beta_last);
    
    // 保存本次电流，供下次计算Δi使用
    state->i_alpha_last = i_alpha;
    state->i_beta_last = i_beta;
    
    // 圆形约束：|x| ≤ λ
    // 防止积分漂移导致磁链幅值偏离
    utils_truncate_number_abs(&(state->x1), lambda);
    utils_truncate_number_abs(&(state->x2), lambda);
    break;
```

**优点**：

- 不需要求导，噪声小
- 计算量比Ortega小（没有 $e$ 的计算）
- 精度和Ortega相当

**就是为啥VESC默认选择MXLEMMING。**

### 2.7 观测器的完整对比

VESC实现了多种观测器，代码里用枚举定义：

```text
typedef enum {
    FOC_OBSERVER_ORTEGA_ORIGINAL = 0,
    FOC_OBSERVER_MXLEMMING,
    FOC_OBSERVER_MXLEMMING_LAMBDA_COMP,
    FOC_OBSERVER_ORTEGA_LAMBDA_COMP,
    FOC_OBSERVER_MXV,
    FOC_OBSERVER_MXV_LAMBDA_COMP,
    FOC_OBSERVER_MXV_LAMBDA_COMP_LIN
} mc_foc_observer_type;
```

![image-20260423202718707](./FOC.assets/image-20260423202718707.png)

**选择建议**：

- **默认用 MXLEMMING**：性能和计算量平衡最好
- **参数不准确**：用 Lambda Comp 版本，在线估计磁链
- **追求极致性能**：用 Ortega，但要保证参数准确
- **低端MCU**：用 MXV，计算量最小

### **2.8 Lambda补偿的必要性**

**问题：电机饱和**

![image-20260423202815160](./FOC.assets/image-20260423202815160.png)

**解决方案：在线估计磁链**

Lambda Comp版本实时估计实际磁链：

```text
// MXLEMMING_LAMBDA_COMP版本
// 误差：估计磁链的平方 - 实际观测到的磁链平方
float err = SQ(state->lambda_est) - (SQ(state->x1) + SQ(state->x2));
 
// 用误差更新磁链估计（类似PI控制器的积分项）
// 0.1 * gamma_half 是更新增益
state->lambda_est += 0.1 * gamma_half * state->lambda_est * (-err) * dt;
 
// 限幅保护（30%-250%）
// 防止估计值跑飞
utils_truncate_number(&(state->lambda_est), lambda * 0.3, lambda * 2.5);
```

**适用场景**：

- 额定电流下磁链下降 > 10% 的电机（内置式永磁电机常见）
- 永磁体部分退磁的老化电机
- 高过载工况（电流 > 1.5倍额定）

### 观测器信号流程图

![image-20260423202953455](./FOC.assets/image-20260423202953455.png)

![img](./FOC.assets/v2-14a4129c8a004fde8cdee7e60a62d5fb_1440w.jpg)

![img](./FOC.assets/v2-3c5738c151cea0162a368ef77fedf2a5_1440w.jpg)

**第一步：更新观测器状态**

```text
foc_observer_update(
  state_now->v_alpha,      // 输入：电压
  state_now->v_beta,
  state_now->i_alpha,      // 输入：电流
  state_now->i_beta,
  dt,                      // 控制周期
  &(motor_now->m_observer_state),  // 观测器状态（x1, x2等）
  &motor_now->m_phase_now_observer,  // 输出：角度
  motor_now);
```

在foc_observer_update函数里（foc_math.c:25）：

```text
void foc_observer_update(float v_alpha, float v_beta, 
                         float i_alpha, float i_beta,
                         float dt, observer_state *state, 
                         float *phase, motor_all_state_t *motor) {
    
    // 获取参数（带温度补偿）
    float R = motor->m_res_temp_comp;  // 温度补偿后的电阻
    float L = conf->foc_motor_l;
    float lambda = conf->foc_motor_flux_linkage;
    
    // 根据配置选择观测器类型
    switch (conf->foc_observer_type) {
        case FOC_OBSERVER_MXLEMMING:
            // ... 如前所述
            break;
        case FOC_OBSERVER_ORTEGA_ORIGINAL:
            // ... 如前所述
            break;
        // ... 其他类型
    }
    
    // 计算角度
    if (phase) {
        *phase = utils_fast_atan2(state->x2 - L*i_beta, 
                                   state->x1 - L*i_alpha);
    }
}
```

**第二步：相位补偿**

（回到control_current）：

```text
// 补偿观测器延迟
motor_now->m_phase_now_observer += 
    motor_now->m_pll_speed * dt * (0.5 + conf_now->foc_observer_offset);
utils_norm_angle_rad((float*)&motor_now->m_phase_now_observer);
```

- `pll_speed`：当前转速（rad/s）
- `dt * 0.5`：半个控制周期的相位变化
- `conf_now->foc_observer_offset`：用户调节的偏移（默认 -1.0）

 ![image-20260423204516964](./FOC.assets/image-20260423204516964.png)

**补偿量详解**：

~~~text
```c
// 补偿公式：Δθ = ω × Δt × (0.5 + offset)
motor_now->m_phase_now_observer += 
    motor_now->m_pll_speed * dt * (0.5 + conf_now->foc_observer_offset);
~~~

**为什么是 0.5？**

- 观测器用的是**当前周期**的 v 和 i
- 但 PWM 输出要到**下一周期**才生效
- 所以需要补偿 0.5 个周期的相位变化

**为什么 offset 默认 -1？**

- 不同观测器延迟特性不同
- offset = -1 时，实际补偿 = 0.5 + (-1) = -0.5
- 相当于不补偿或反向补偿
- 需要根据实测效果调整（通常 -1.5 到 0.5 之间）

## 三，SMO滑膜观测器

### 第一部分：参数预测

![image-20260423211919405](./FOC.assets/image-20260423211919405.png)

![image-20260423212420571](./FOC.assets/image-20260423212420571.png)

![image-20260423212611683](./FOC.assets/image-20260423212611683.png)

**这里的sign()就是自变量大于0就输出1，小于0就输出-1**

![image-20260424112345171](./FOC.assets/image-20260424112345171.png)

**接下来要确定一个合适的h值**

**李亚普洛夫证明**

![image-20260424114101295](./FOC.assets/image-20260424114101295.png)

![image-20260424114120429](./FOC.assets/image-20260424114120429.png)

**得到系统框图**

![image-20260424114202730](./FOC.assets/image-20260424114202730.png)

### 锁相跟随

![image-20260424123710825](./FOC.assets/image-20260424123710825.png)

![image-20260424123721572](./FOC.assets/image-20260424123721572.png)

 

![image-20260424124615541](./FOC.assets/image-20260424124615541.png)

![image-20260424125057054](./FOC.assets/image-20260424125057054.png)

![image-20260424125250586](./FOC.assets/image-20260424125250586.png)

### 

