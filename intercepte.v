module intercepte 
(
input clk50, reset,								// inputs: clk_50 MHz, reset,
input start, pause, fire,						// in: botões do game
input [NCHV-1:0] ChvCode,						// in chave código bits para shift
output LEDGameOver,								// led timeout (fim do game - ldGreen[8])
output LEDPause1, LEDPause2,					// led pause no game (DISP4/5 seg 'g')
output reg [SZGR-1:0] SR_GR,					// leds verde para mísseis
output reg [SZRD-1:0] SR_RD,					// led vermelhos 
output reg[6:0] DscM,							// score 7 segs do display para milhar 
output reg[6:0] DscC,							// score 7 segs do display para centena
output reg[6:0] DscD,							// score 7 segs do display para dezena
output reg[6:0] DscU,							// score 7 segs do display para unidade
output reg [6:0] DcrD,							// cronometro 7 segs dos displays para dezena
output reg [6:0] DcrU							// cronometro 7 segs dos displays para unidade
 ); 
  
parameter SZRD = 18;                 		// qtde de leds vermelhos
parameter SZGR = 8;                  		// qtde de leds verdes
parameter TIME_DEB = 32'd10_000_000; 		// tempo de debouncing em 200 ms
parameter TIME_FIRE = 32'd5_000_000; 		// tempo do strobe do fire = 100 ms
parameter TIPO_DISPLAY = 0;          		// =0:ânodo =1:cátodo comum
parameter NCHV = 8;                  		// num bits entrada regs
parameter NBITS_CHV = (NCHV<2)? 1: (NCHV<4)? 2: (NCHV<8)? 3:(NCHV<16)? 4: (NCHV<32)? 5: 6;
  

reg [2:0]Zout;

// fios, assigns, lógica combinacional para controlar clocks 
wire clk_RD, clk_GR, clk_CRN;        		// os sinais de clock RG, GR, CRN
assign clk_RD = clk5Hz & Zout[0];    		// clk gated leds RED, bit Zout[0]
assign clk_GR = clk10Hz & Zout[0];   		// clk gated leds GREEN
assign clk_CRN= clk1Hz & Zout[0];    		// clk gated CRONO  
assign LEDGameOver = Zout[2];        		// led GAMEOVER, bit Zout[2]
assign LEDPause1 = Zout[1];          		// led PAUSED1, bit Zout[1]
assign LEDPause2 = Zout[1];          		// led PAUSED2, bit zout[1] também

 
// registradores do debouncing para as 4 keys de entrada do game
reg [31:0] Cnt_start, Cnt_pause, Cnt_fire;
reg stb_start, stb_pause, stb_fire;
  
 
// Máquina de Estados do funcionamento principal do jogo 
reg [2:0] Estado;                    		// (reg) memória dos Estados da FSM

// Estados da FSM de funcionamento principal
parameter INICIAL=0, JOGANDO=1, PAUSE=2, PAUSE1=3, PAUSE2=4, GAMEOVER=5;

always @ (negedge clk50 or negedge reset) 
begin
	if (!reset)                  				// se reset = 0 (botão do reset foi pressionado)
	begin
		Estado <= INICIAL;        				// A máquina permanece no Estado INICIAL (crônometro fica em 59s e score em 0000)
		Zout <= 3'b000;							// bloqueia o clocks, deixa apagado o LED de fim de jogo e liga o display
		
	end
	else
	begin
	case (Estado)									// Estados da FSM principal do jogo
		INICIAL:										// se em estado INICIAL
		begin
			Zout <= 3'b000;						// bloqueia os clocks e deixa apagado o LED de fim de jogo e desliga o display
			if (stb_start == 'b1)				// se o botão do start for pressionado a máquina passa para o estado JOGANDO
				Estado <= JOGANDO;
			else 
				Estado <= INICIAL;				// caso contrário, permanece no estado INICIAL
		end
			
		JOGANDO:										// se em estado JOGANDO
		begin
			Zout <= 3'b011;						// libera os clocks, deixa apagado o LED de fim de jogo e desliga o display			
			if (stb_pause == 'b1)				// se o botão do pause for pressionado a máquina passa para o estado PAUSE          
				Estado <= PAUSE;
			else if ((crU == 4'b0) && (crD == 4'b0)) // se o cronômetro zerar o jogo acaba e a máquina passa para o estado GAMEOVER 
				Estado <= GAMEOVER;
				else
					Estado <= JOGANDO;				// caso contrário, a máquina permanece no estado JOGANDO
		end
			
		PAUSE:										// se em estado PAUSE
		begin
			Zout <= 3'b000;						// bloqueia os clocks, deixa apagado o LED de fim de jogo e desliga o display
			if (stb_pause == 'b1)				// se o botão do pause for pressionado pela primeira vez, a máquina permanece no estado PAUSE
				Estado <= PAUSE;
			else
				Estado <= PAUSE1;					// quando o stb_pause = 0, a máquina passa para o estado PAUSE1
		end
			
		PAUSE1:										// se em estado PAUSE1
		begin
			if (stb_pause == 'b0)				// enquanto o stb_pause = 0, a máquina permanece no estado PAUSE1
				Estado <= PAUSE1;
			else
				Estado <= PAUSE2;					// quando o botão do pause for pressionado novamente, a máquina passa para o estado PAUSE2
		end
			
		PAUSE2:										// se em estado PAUSE2
		begin
			if (stb_pause == 'b1)				// enquanto stb_pause = 1, a máquina permanece no estado PAUSE2
				Estado <= PAUSE2;
			else
				Estado <= JOGANDO;				// quando o stb_pause = 0, a máquina passa para o estado JOGANDO
		end
			
		GAMEOVER:									// se em estado GAMEOVER   
		begin
			Estado <= GAMEOVER;					// a máquina permanece no estado GAMEOVER
			Zout = 3'b100;							// bloqueia o clocks e liga o LED de fim de jogo e o display
		end          
			
		default:
			Estado <= INICIAL;					// default do estado INICIAL
	endcase
	end
end

// Deslocamento LEDs vermelhos (misseis vermelhos)
reg [3:0] counter1;           // Contador de 5 bits para rastrear o número de deslocamentos
reg invert_flag;             // Flag de 1 bit para alternar entre o código original e o invertido
reg [7:0] ChvCode_inv;       // Versão invertida do ChvCode (8 bits)

// Bloco combinacional para inverter ChvCode e armazenar em ChvCode_inv
always @(*) begin
	ChvCode_inv = ~ChvCode; // Inverte todos os bits de ChvCode
end
    
// Bloco sequencial, executado na borda de subida do clock ou quando o reset é ativado
always @(posedge clk_RD or negedge reset)
begin
	if (!reset)
	begin
		SR_RD <= 18'b0;
		counter1 <= 4'b0;
		invert_flag <= 1'b0;
	end
	else
	begin
		if (invert_flag == 1'b0)
		begin
			if (counter1 < NCHV)
			begin
				SR_RD <= SR_RD >> 1;
				SR_RD [17]<= ChvCode[counter1];
				counter1 <= counter1 + 1;
			end
			else
			begin
				invert_flag <= 1'b1;
				counter1 <= 4'b0;
			end
		end
		else if (invert_flag == 1'b1)
		begin
			if (counter1 < NCHV)
			begin
				SR_RD <= SR_RD >> 1;
				SR_RD [17]<= ChvCode_inv[counter1];
				counter1 <= counter1 + 1;
			end
			else
			begin
				invert_flag <= 1'b0;
				counter1 <= 4'b0;
			end
		end
	end
end

// Deslocamento LEDs verdes (misseis verdes)
always @(posedge clk_GR or negedge reset)     
begin                      	
	if (!reset)
		SR_GR <= 8'b0;
	else
	begin
		SR_GR <= SR_GR << 1;
		SR_GR[0] <= stb_fire;
	end
end                        
  
// instancia divisor (clk_div) e atualiza o par (kte NclkDIV) do modulo
clk_div #( .NclkDIV (24_999_999)) ckDv1		// inst clk_div, redefine NclkDIV
  (                                    		// mapear ports do módulo
  .clk    ( clk50 ),                   		// clk daquele mod liga no clk50 daqui
  .reset  ( reset),                    		// reset de lá em reset daqui
  .clkOut ( clk1Hz )                   		// clkOut de lá em clk1Hz daqui
  );
  
 clk_div_10 #( .NclkDIV (2_499_999)) ckDv10	// inst clk_div, redefine NclkDIV
  (                                    		// mapear ports do módulo
  .clk    ( clk50 ),                   		// clk daquele mod liga no clk50 daqui
  .reset  ( reset),                    		// reset de lá em reset daqui
  .clkOut ( clk10Hz )                  		// clkOut de lá em clk10Hz daqui
  );
  
  clk_div_5 #( .NclkDIV (4_999_999)) ckDv5	// inst clk_div, redefine NclkDIV
  (                                    		// mapear ports do módulo
  .clk    ( clk50 ),                   		// clk daquele mod liga no clk50 daqui
  .reset  ( reset),                    		// reset de lá em reset daqui
  .clkOut ( clk5Hz )                   		// clkOut de lá em clk5Hz daqui
  );
 
// Cronômetro que inicia em 59s e descrece
reg [3:0] crU;
reg [3:0] crD;

always@(posedge clk_CRN or negedge reset)
begin
	if(reset == 0) 
	begin
		crU <= 4'd9;
		crD <= 4'd5;
	end
	else if(crU > 4'd0)
	begin
		crU <= crU-4'd1;
	end
		else if(crD == 0)
		begin
			crD <=4'd0;
			crU <=4'd0;
		end
			else
			begin
				crD <= crD - 4'd1;
				crU <= 4'd9;
	end
end

always @(posedge clk1Hz)
begin
	case(crU)                    
      4'b0000: DcrU <= 7'b1000000;
      4'b0001: DcrU <= 7'b1111001;
      4'b0010: DcrU <= 7'b0100100;
      4'b0011: DcrU <= 7'b0110000;
      4'b0100: DcrU <= 7'b0011001;
      4'b0101: DcrU <= 7'b0010010;
      4'b0110: DcrU <= 7'b0000010;
      4'b0111: DcrU <= 7'b1111000;
      4'b1000: DcrU <= 7'b0000000;
      4'b1001: DcrU <= 7'b0010000;
		default: DcrU <= 7'b0111111;
	endcase
end

always @(posedge clk1Hz)
begin
	case(crD)                    
		4'b0000: DcrD <= 7'b1000000;
		4'b0001: DcrD <= 7'b1111001;
		4'b0010: DcrD <= 7'b0100100;
		4'b0011: DcrD <= 7'b0110000;
		4'b0100: DcrD <= 7'b0011001;
      4'b0101: DcrD <= 7'b0010010;
      4'b0110: DcrD <= 7'b0000010;
      4'b0111: DcrD <= 7'b1111000;
      4'b1000: DcrD <= 7'b0000000;
      4'b1001: DcrD <= 7'b0010000;
      default: DcrD <= 7'b0111111;
   endcase
end 

// Score que inicia em 0000
reg [3:0] scrM;
reg [3:0] scrC;
reg [3:0] scrD;
reg [3:0] scrU;
reg signed [15:0] score, temp_score;      // Registrador para armazenar a pontuação
//reg [3:0] hit_count;   // Contador de acertos

always @(negedge clk_GR or negedge reset)
begin
	if (!reset)
		begin
			score <= 0;    // Inicializa o score
		end
	else if ((SR_GR[7] == 'b1) && (SR_RD[0] == 'b1)) // Checa se o tiro acerta o alvo
		begin
			score <= score + 50;  // Adiciona 25 pontos por acerto
		end
	else if ((SR_GR[7] == 'b1) && (SR_RD[0] == 'b0)) // Checa se o tiro erra o alvo
		begin
			score <= score - 5;  // Subtrai 5 pontos por erro
		end
	else if ((SR_GR[7] == 'b0) && (SR_RD[0] == 'b1))
		begin
				score <= score - 5;  // Subtrai 5 pontos por erro
		end
end

// valores possíveis para o score
parameter MAXSCORE_MIL = 9999;

reg [1:0] estados_score;
// Separação dos milhares, das centenas, das dezenas e unidades
always @(posedge clk50 or negedge reset)
begin
	if (!reset)
		begin
			temp_score <= 0;
			estados_score <= 2'b00;    // Inicializa o score
		end	
    else if (score >= MAXSCORE_MIL && estados_score == 2'b00)
		begin
			temp_score <= 9999;
			estados_score <= 2'b01;
		end
	else if (score < 0 && estados_score == 2'b00)
			begin
				temp_score <= 0;
				estados_score <= 2'b01;
			end
	else if (estados_score == 2'b00)
		begin
			temp_score = score;
			estados_score <= 2'b01;
		end
	else if (estados_score == 2'b01)
		begin
        scrM <= (score / 1000);  // atribui o valor da divisão por 1000
		  scrC <= (score % 1000) / 100;  // atribui o valor da divisão por 100
		  scrD <= (score / 100) / 10;   // atribui o valor da divisão por 10
		  scrU <= (score % 10);
		  estados_score <= 2'b10;
		end
	else if (estados_score == 2'b10)
		estados_score <= 2'b00;
end


always @(posedge clk50)
begin
	case(scrM)                    
      4'b0000: DscM <= 7'b1000000;
      4'b0001: DscM <= 7'b1111001;
      4'b0010: DscM <= 7'b0100100;
      4'b0011: DscM <= 7'b0110000;
      4'b0100: DscM <= 7'b0011001;
      4'b0101: DscM <= 7'b0010010;
      4'b0110: DscM <= 7'b0000010;
      4'b0111: DscM <= 7'b1111000;
      4'b1000: DscM <= 7'b0000000;
      4'b1001: DscM <= 7'b0010000;
      default: DscM <= 7'b0111111;
	endcase
end

always @(posedge clk50)
begin
	case(scrC)                    
      4'b0000: DscC <= 7'b1000000;
      4'b0001: DscC <= 7'b1111001;
      4'b0010: DscC <= 7'b0100100;
      4'b0011: DscC <= 7'b0110000;
      4'b0100: DscC <= 7'b0011001;
      4'b0101: DscC <= 7'b0010010;
      4'b0110: DscC <= 7'b0000010;
      4'b0111: DscC <= 7'b1111000;
      4'b1000: DscC <= 7'b0000000;
      4'b1001: DscC <= 7'b0010000;
      default: DscC <= 7'b0111111;
	endcase
	end

always @(posedge clk50)
begin
	case(scrD)                    
      4'b0000: DscD <= 7'b1000000;
      4'b0001: DscD <= 7'b1111001;
      4'b0010: DscD <= 7'b0100100;
      4'b0011: DscD <= 7'b0110000;
      4'b0100: DscD <= 7'b0011001;
      4'b0101: DscD <= 7'b0010010;
      4'b0110: DscD <= 7'b0000010;
      4'b0111: DscD <= 7'b1111000;
      4'b1000: DscD <= 7'b0000000;
      4'b1001: DscD <= 7'b0010000;
      default: DscD <= 7'b0111111;
	endcase
end

always @(posedge clk50)
begin
	case(scrU)                    
      4'b0000: DscU <= 7'b1000000;
      4'b0001: DscU <= 7'b1111001;
      4'b0010: DscU <= 7'b0100100;
      4'b0011: DscU <= 7'b0110000;
      4'b0100: DscU <= 7'b0011001;
      4'b0101: DscU <= 7'b0010010;
      4'b0110: DscU <= 7'b0000010;
      4'b0111: DscU <= 7'b1111000;
      4'b1000: DscU <= 7'b0000000;
      4'b1001: DscU <= 7'b0010000;
      default: DscU <= 7'b0111111;
	endcase
end
	
 // esse circuito mantém o 'stb_fire' = 1 por ~> 100 ms
reg [1:0] stt_fired;									// reg estados do strobe fired

always @(posedge clk50 or negedge reset)		// debouncing da tecla fire
begin
	if (reset=='b0)									// no reset 
	begin
		Cnt_fire <= 32'b0;							// reseta contador
		stb_fire <= 'b0;								// zera sinal stb_fire
		stt_fired <= 2'b00;							// zera o estado da maq
	end
	else													// saiu do reset
	begin													// baixa bt fire, contador zerado e está no estado 2b00?
		if ((fire=='b0) && (stt_fired==2'b00))	// baixou bt fire
		begin
			stt_fired <= 2'b01;						// prox estado 01
			stb_fire <= 'b1;							// faz o stb_fire = 1
			Cnt_fire <= TIME_FIRE;					// carrega cont c/ TIME_FIRE
		end
		else if ((Cnt_fire > 0) && (stt_fired==2'b01))
		begin
			Cnt_fire <= Cnt_fire - 1;				// dec time do strobe
		end
			else if ((Cnt_fire == 0) && (stt_fired==2'b01))
			begin
				stt_fired <= 2'b10;					// muda para estado 10
				stb_fire <= 'b0;						// volta o stb_fire = 0
			end
				else if ((fire=='b1) && (stt_fired==2'b10)) // qdo fired=1 (soltar bot)
				begin
					stt_fired <= 2'b11;				// estado 11 = subiu o botão
					Cnt_fire <= TIME_FIRE;			// carregaa cont c/ TIME_FIRE
				end
					else if ((Cnt_fire > 0) && (stt_fired==2'b11))
					begin
						Cnt_fire <= Cnt_fire - 1;		// dec time do strobe
					end
						else if ((Cnt_fire == 0) && (stt_fired==2'b11))
						begin
							stt_fired <= 2'b00;			// volta p/ estado 00
						end
		end
end
  
// debouncing da tecla start
always @(posedge clk50 or negedge reset) 
begin
	if (reset=='b0)										// no reset 
	begin
		Cnt_start <= TIME_DEB;							// recomeça contador com TIME_DEB
		stb_start <= 'b0;									// zera sinal stb_start
	end
	else														// saiu do reset
	begin
		if ((start=='b0) && (stb_start=='b0))		// descida do start
			stb_start <= 'b1;              			// faz o stb_start = 1
		else if ((stb_start=='b1) && (Cnt_start>32'b0)) // stb=1, cont>0?
			Cnt_start <= Cnt_start-1;     			// só decrementa contador 
			else if ((start=='b1) && (Cnt_start==32'b0)) // botão voltou p/ '1'?
			begin
				Cnt_start <= TIME_DEB;					// carrega timer com TIME_DEB
				stb_start <= 'b0;							// retorna stb_fire = 0
			end
	end
end

// debouncing da tecla pause
always @(posedge clk50 or negedge reset) 
begin
	if (reset=='b0)										// no reset 
	begin
		Cnt_pause <= TIME_DEB;							// recomeça contador com TIME_DEB
		stb_pause <= 'b0;									// zera sinal stb_pause
	end
	else														// saiu do reset
	begin
		if ((pause=='b0) && (stb_pause=='b0))		// descida do pause
			stb_pause <= 'b1;								// faz o stb_pause = 1
			else if ((stb_pause=='b1) && (Cnt_pause>32'b0)) // stb=1, cont>0?
				Cnt_pause <= Cnt_pause-1;				// só decrementa contador
				else if ((pause=='b1) && (Cnt_pause==32'b0)) // botão voltou p/ '1'?
				begin
					Cnt_pause <= TIME_DEB;				// carrega timer com TIME_DEB
					stb_pause <= 'b0;						// retorna stb_fire = 0
				end
	end
end
endmodule