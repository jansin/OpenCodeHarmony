import { appStore } from '../data/AppStore';
import { TodoItem } from '../common/model/Types';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import { SoftTopBar, SoftChip, SoftEmptyState } from '../common/ui/SoftChrome';
import { SoftLightSense } from '../common/ui/SoftLightSense';

@Component
export struct TodoView {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  onBack: (() => void) = () => {
  };

  @State todos: TodoItem[] = [];
  @State appear: number = 0;

  private onReview = (): void => {
    this.todos = appStore.getTodos();
  };

  aboutToAppear(): void {
    this.todos = appStore.getTodos();
    appStore.on('review', this.onReview);
    appStore.refreshTodos();
    setTimeout(() => {
      this.getUIContext().animateTo(Motion.enterOpt(), () => {
        this.appear = 1;
      });
    }, 30);
  }

  aboutToDisappear(): void {
    appStore.off('review', this.onReview);
  }

  private statusText(s: string): string {
    if (s === 'completed') {
      return '完成';
    } else if (s === 'in_progress') {
      return '进行中';
    }
    return '待办';
  }

  private doneCount(): number {
    let n = 0;
    for (let i = 0; i < this.todos.length; i++) {
      if (this.todos[i].status === 'completed') {
        n++;
      }
    }
    return n;
  }

  build() {
    Column() {
      SoftTopBar({
        title: '待办',
        onBack: () => {
          this.onBack();
        }
      })

      Row() {
        Text(this.todos.length > 0
          ? ('进度 ' + this.doneCount().toString() + ' / ' + this.todos.length.toString())
          : '暂无任务')
          .fontSize(Theme.typeBodySm)
          .fontColor(Theme.textSecondary)
          .layoutWeight(1)
        SoftChip({
          label: '刷新',
          onTap: () => {
            appStore.refreshTodos();
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      if (this.todos.length === 0) {
        Column() {
          SoftEmptyState({
            title: '还没有待办',
            subtitle: 'Agent 规划任务后会显示在这里'
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .opacity(1)
      } else {
        List({ space: 10 }) {
          ForEach(this.todos, (t: TodoItem) => {
            ListItem() {
              Row({ space: 12 }) {
                SoftChip({
                  label: this.statusText(t.status),
                  active: t.status === 'in_progress'
                })

                Text(t.title)
                  .fontSize(Theme.typeBody)
                  .fontColor(Theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding(14)
              .backgroundColor(Theme.glassBg())
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .borderRadius(Theme.radiusMd)
              .border({ width: 0.5, color: Theme.borderMuted })
              .visualEffect(SoftLightSense.card())
              .shadow({ radius: 10, color: Theme.shadowSoft, offsetX: 0, offsetY: 3 })
            }
            .transition(Motion.cardIn())
          }, (t: TodoItem) => t.id + t.status)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: 16 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .opacity(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bgPrimary)
  }
}
