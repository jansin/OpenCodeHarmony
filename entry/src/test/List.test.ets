import localUnitTest from './LocalUnit.test';
import typesTest from './Types.test';

export default function testsuite() {
  localUnitTest();
  typesTest();
}