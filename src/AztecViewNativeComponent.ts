import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';
import type { ViewProps } from 'react-native';
import type { Int32, WithDefault, DirectEventHandler, Float } from 'react-native/Libraries/Types/CodegenTypes';
// text: chapter.text || '',
//   selection: { start: this.selectionStart, end: this.selectionEnd },
// eventCount: this.lastEventCount,
type NativeTextProp = Readonly<{
  text?: string;
  selection?: Readonly<{start?: WithDefault<Int32, 0>; end?: WithDefault<Int32, 0>}>;
  eventCount?: Float;
}>;
type NativeParametersProp = Readonly<{
  story_id?: string;
  chapter_id?: string;
}>;
type NativeHeadersProp = Readonly<{
  locale?: string;
  'app-version'?: string;
  os?: string;
}>;

interface NativeProps extends ViewProps {
  color?: Int32;
  text?: NativeTextProp;
  placeholder?: string;
  parameters?: NativeParametersProp;
  headers?: NativeHeadersProp;
  activeFormats?: string[];
  imageUrl?: string;
  fontSize?: Float;
  fontFamily?: string;
  disableAutocorrection?: boolean;
}

export default codegenNativeComponent<NativeProps>('AztecView');
