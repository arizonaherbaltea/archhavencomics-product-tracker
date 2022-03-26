
test=$(cat << EOF
asdf
gfa
jff
EOF
)
testvar=sdfasg
while read -r line; do
  echo "$line"
  testvar=$line
done <<< $test

echo $testvar

function pipetest1 {
  if (( $# == 0 )) ; then
    cat -A < /dev/stdin | tee -a test.log
  else
    cat -A <<< "$@"  | tee -a test.log
  fi
}
function pipetest2 {
  if (( $# == 0 )) ; then
    sed -r 's/hell/hull/g'  < /dev/stdin | tee -a test.log
  else
    sed -r 's/hell/hull/g'  <<< "$@"  | tee -a test.log
  fi
}
function pipetest3 {
  if (( $# == 0 )) ; then
    grep -Eo 'ullo world'  < /dev/stdin | tee -a test.log
  else
    grep -Eo 'ullo world'   <<< "$@"  | tee -a test.log
  fi
}
function pipetestloop {
  local i=0
  if (( $# == 0 )) ; then
    while read -r line; do echo "$i $line"; i=$((i+1)); done   < /dev/stdin | tee -a test.log
  else
    while read -r line; do echo "$i $line"; i=$((i+1)); done   <<< "$@"  | tee -a test.log
  fi
}

echo -e "hello world\ntest hell" |  pipetest1 | pipetest2 | pipetest3

echo -e "hello world\ntest hell\nloop"  | pipetestloop
pipetestloop "$(echo -e "hello world\ntest hell\nloop")"



######
TEST_COURSE=''
function testfail {
  return 0
}
function testfunc {
  TEST_COURSE="/tmp/${SOURCE_NAME}-$(generate-uuid)"
}
testfail | testfunc
echo "$TEST_COURSE"