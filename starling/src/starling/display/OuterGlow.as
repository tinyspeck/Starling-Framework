package starling.display {
	import com.adobe.utils.AGALMiniAssembler;
	
	import flash.display3D.Context3D;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Program3D;
	
	import starling.core.Starling;
	import starling.textures.ConcreteTexture;
	import starling.textures.SubTexture;
	import starling.textures.Texture;

	/**
	 * Creates a program and constants that will draw an outline around a texture's opaque pixels. 
	 * The outline is only drawn if the quad has a color other than 0xffffff 
	 * (starling considers non white color as being tinted).
	 */ 
	public class OuterGlow {
		
		public static const instance:OuterGlow = new OuterGlow();
		private static const programPrefix:String = "OMC_";
		
		private const uvOperationConstants:Vector.<Number> = new Vector.<Number>(4, true);
		private const zeroConstant:Vector.<Number> = new Vector.<Number>(4, true);
		private const oneConstant:Vector.<Number> = new Vector.<Number>(4, true);
		private const outlineColorConstant:Vector.<Number> = new Vector.<Number>(4, true);
		private const stepConstants:Vector.<Number> = new Vector.<Number>(4, true);
		
		private var _scale:Number = 1.4;
		private var _size:uint = 3;
		
		public function OuterGlow() {
			if (instance) {
				throw new Error("Singleton, use '.instance' instead.");
			}
			
			buildOutlineProgram();
			setupOutlineProgramConstants();
		}
		
		public function setupDrawDependencies(context:Context3D, texture:Texture):void {
			
			setNormalizedUVConstants(texture);
			
			var program:Program3D = Starling.current.getProgram(getProgramName());
			if (!program) program = buildOutlineProgram();
			
			context.setProgram(program);
			context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, uvOperationConstants);
			context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, oneConstant);
			context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 2, zeroConstant);
			context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 3, outlineColorConstant);
			context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 4, stepConstants);
		}
		
		private function getProgramName():String {
			return programPrefix + _size + _scale
		}

		private function buildOutlineProgram():Program3D {			
			var vertexProgramCode:String =
				"m44 op, va0, vc1 \n" + // 4x4 matrix transform to output clipspace
				"mul v0, va1, vc0 \n" + // multiply alpha (vc0) with color (va1)
				"mov v1, va2      \n";   // pass texture coordinates to fragment program
			
			var fragmentProgramCode:String = 
				"mov ft6, fc2 \n" +
				"mov ft3, fc2 \n" +
				
				buildOutlineOps(true, false, false, false, _size) +	// left
				buildOutlineOps(true, false, true, false, _size) +		// right 
				buildOutlineOps(false, true, false, false, _size) +	// up
				buildOutlineOps(false, true, false, true, _size) +		// down
				buildOutlineOps(true, true, false, false, _size) +		// left up
				buildOutlineOps(true, true, false, true, _size) +		// left down
				buildOutlineOps(true, true, true, false, _size) +		// right up
				buildOutlineOps(true, true, true, true, _size) +		// right down	
				
				"mul ft6, fc3, ft3.w \n" 							+ 	// copy outline color
				"tex ft1, v1, fs0<2d,clamp,linear,mipnone> \n" 		+  	// sample texture 1
				"sub ft4, fc1, ft1.w \n" 							+	// subtract 1 - fragment alpha to determine if we show outline
				"mul ft6, ft6, ft4.w \n" 							+	// show outline color if fragment alpha < 1		
				"add ft1, ft1, ft6    \n"							+ 	// add outline color to fragment
				"mul oc, ft1, v0 \n";									// multiply output by DisplayObject color property
			
			var vertexProgramAssembler:AGALMiniAssembler = new AGALMiniAssembler();
			vertexProgramAssembler.assemble(Context3DProgramType.VERTEX, vertexProgramCode);
			
			var fragmentProgramAssembler:AGALMiniAssembler = new AGALMiniAssembler();
			fragmentProgramAssembler.assemble(Context3DProgramType.FRAGMENT, fragmentProgramCode); 
			
			var programName:String = getProgramName();
			Starling.current.registerProgram(programName, vertexProgramAssembler.agalcode, fragmentProgramAssembler.agalcode);
			return Starling.current.getProgram(programName);
		}
		
		private function buildOutlineOps(x:Boolean, y:Boolean, invertX:Boolean, invertY:Boolean, iterations:uint = 4):String {
			
			var yOperator:String = "add";
			var xOperator:String = "add";
			if (invertX) {
				xOperator = "sub"
			} 
			if (invertY){
				yOperator = "sub";
			}
			
			var outlineOpCodes:String = 
				"mov ft5, fc0 \n";	// copy fresh uvOperationConstants										
			for (var i:uint = 0; i < iterations; i++) {
				
				outlineOpCodes += "mov ft2, v1 \n";	// copy unmodified uv 
				
				if (x && y && (invertX == invertY)) {
					outlineOpCodes += xOperator + " ft2.xy, v1.xy, ft5.xy \n"			// offset both u and v
				} else {
					if (x) outlineOpCodes += xOperator + " ft2.x, v1.x, ft5.x \n";	// offset u
					if (y) outlineOpCodes += yOperator + " ft2.y, v1.y, ft5.y \n";	// offset v
				}
				outlineOpCodes += 
					"tex ft2, ft2, fs0<2d,clamp,linear,mipnone> \n" 	+	// fragment
					"mul ft2.w, ft2.w, ft5.z \n" 						+	// multiply fragment alpha by alpha for current offset
					"max ft3.w, ft3.w, ft2.w \n" 						+	// if the alpha is larger than previous iteration, save it
					"add ft5.xy, ft5.xy, fc4.xy \n" 					+	// increment uv step
					"sub ft5.z, ft5.z, fc4.z \n";   						// decrement alpha
			}
			
			return outlineOpCodes;
		}		
		
		private function setupOutlineProgramConstants():void {
			
			stepConstants[2] = 1.0/_size;	// alpha step size
			stepConstants[3] = 0; 					// not used
			
			uvOperationConstants[2] = 1; 			// current alpha
			uvOperationConstants[3] = 0; 			// not used
			
			zeroConstant[0] = zeroConstant[1] = zeroConstant[2] = zeroConstant[3] = 0;
			oneConstant[0] = oneConstant[1] = oneConstant[2] = oneConstant[3] = 1;
			
			// default outline color to cyan
			setColor(0.4, 0.85, 1, 0.8);
		}
		
		private function setNormalizedUVConstants(texture:Texture):void {
			var tp:Texture = texture;
			if (!(tp is ConcreteTexture)) {
				tp = (tp as SubTexture).parent;
			}
		
			var normalizedU:Number = 1/tp.width;
			var normalizedV:Number = 1/tp.height;
			
			stepConstants[0] = normalizedU * _scale;	// u fragment step size
			stepConstants[1] = normalizedV * _scale;	// v fragment step size
			
			uvOperationConstants[0] = stepConstants[0];	// current U
			uvOperationConstants[1] = stepConstants[1];	// current V
		}
		
		public function setColor(r:Number, g:Number, b:Number, a:Number = 1):void {
			outlineColorConstant[0] = r;
			outlineColorConstant[1] = g;
			outlineColorConstant[2] = b;
			outlineColorConstant[3] = a;
		}	
		
		public function get size():uint { return _size; }
		public function set size(value:uint):void {
			_size = value;
			setupOutlineProgramConstants();
		}
		
		public function get scale():uint { return _scale; }
		public function set scale(value:uint):void {
			_scale = value;
			setupOutlineProgramConstants();
		}		
	}
}